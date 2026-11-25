import Foundation

/// Loads the copies of the guides that ship inside the build, bundled from `docs/guides`.
public struct BundledGuideLoader: GuideLoading {
  /// The guides, in the order of the table of chapter 16 §16.
  static let names = [
    "getting-started",
    "writing-use-cases",
    "finding",
    "linking",
    "verifying",
    "reading-status",
    "ci-and-hooks",
    "quirks",
  ]

  private let bundle: Bundle
  private let parser: any GuideParsing

  /// Makes the loader.
  public init() {
    self.init(
      bundle: .module,
      parser: GuideParser(),
    )
  }

  init(
    bundle: Bundle,
    parser: any GuideParsing,
  ) {
    self.bundle = bundle
    self.parser = parser
  }

  public func guides() throws(GuideLoadingError) -> [Guide] {
    var guides: [Guide] = []

    for name in Self.names {
      try guides.append(guide(named: name))
    }

    return guides
  }

  /// The bytes of the bundled copy, exactly as shipped.
  func guideData(named name: String) throws(GuideLoadingError) -> Data {
    guard
      let url = bundle.url(
        forResource: name,
        withExtension: "md",
        subdirectory: "Guides",
      ),
      let data = try? Data(contentsOf: url)
    else {
      throw .missing(name)
    }

    return data
  }

  private func guide(named name: String) throws(GuideLoadingError) -> Guide {
    guard let text = try String(
      data: guideData(named: name),
      encoding: .utf8,
    ) else {
      throw .unreadable(name)
    }

    do {
      return try parser.guide(
        named: name,
        text: text,
      )
    } catch {
      throw .invalid(name)
    }
  }
}
