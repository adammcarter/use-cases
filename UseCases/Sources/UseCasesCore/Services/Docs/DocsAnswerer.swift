import Foundation

/// Lists the guides, shows the one a name is exactly, and searches their sections for anything
/// else.
public struct DocsAnswerer: DocsAnswering {
  private let loader: any GuideLoading
  private let planner: any GuidePlanning
  private let searcher: any GuideSearching

  /// Makes the answerer, reading the guides bundled with the build.
  public init() {
    self.init(
      loader: BundledGuideLoader(),
      planner: GuidePlanner(),
      searcher: GuideSearcher(),
    )
  }

  /// Makes the answerer from its parts.
  public init(
    loader: any GuideLoading,
    planner: any GuidePlanning,
    searcher: any GuideSearching,
  ) {
    self.loader = loader
    self.planner = planner
    self.searcher = searcher
  }

  public func answer(_ request: DocsRequest) throws(DocsError) -> DocsAnswer {
    switch request {
    case .list:
      return try .list(guides())
    case let .words(words, isExact, pageSize):
      let plan: GuidePlan

      do {
        plan = try planner.plan(
          words: words,
          isExact: isExact,
          pageSize: pageSize,
        )
      } catch {
        throw .search(error)
      }

      let guides = try guides()

      // A guide's exact name shows that guide, as an exact id wins in `status`.
      if let guide = guides.first(where: { guide in
        guide.name == words.trimmingCharacters(in: .whitespaces)
      }) {
        return .guide(guide)
      }

      return try page(
        plan,
        in: guides,
      )
    case let .continuing(token):
      let plan: GuidePlan

      do {
        plan = try planner.plan(continuing: token)
      } catch {
        throw .search(error)
      }

      return try page(
        plan,
        in: guides(),
      )
    }
  }

  private func guides() throws(DocsError) -> [Guide] {
    do {
      return try loader.guides()
    } catch {
      throw .guides(error)
    }
  }

  private func page(
    _ plan: GuidePlan,
    in guides: [Guide],
  ) throws(DocsError) -> DocsAnswer {
    do {
      return try .page(
        searcher.search(
          plan,
          in: guides,
        ),
      )
    } catch {
      throw .search(error)
    }
  }
}
