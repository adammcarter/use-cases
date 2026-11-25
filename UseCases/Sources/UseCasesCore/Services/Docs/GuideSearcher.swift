/// Matches the words of a search to the sections of the guides with the matcher `search` uses, so
/// a typo, a `"phrase"` and a `-word` mean the same in both.
public struct GuideSearcher: GuideSearching {
  /// How much a match in a section's heading counts: as much as a use case's title.
  static let headingWeight = 10

  /// How much a match in a section's text counts.
  static let bodyWeight = 3

  private let matcher: any TextMatching
  private let digester: any SearchDigesting
  private let codec: any SearchTokenCoding
  private let hasher: any Hashing

  /// Makes the searcher.
  public init() {
    self.init(
      matcher: TextMatcher(),
      digester: SearchDigester(),
      codec: SearchTokenCodec(),
      hasher: SHA256Hasher(),
    )
  }

  init(
    matcher: any TextMatching,
    digester: any SearchDigesting,
    codec: any SearchTokenCoding,
    hasher: any Hashing,
  ) {
    self.matcher = matcher
    self.digester = digester
    self.codec = codec
    self.hasher = hasher
  }

  public func search(
    _ plan: GuidePlan,
    in guides: [Guide],
  ) throws(GuideSearchError) -> GuidePage {
    let state = digest(of: guides)

    if let seal = plan.seal,
       seal != digester.seal(
         of: plan.parameters,
         state: state,
       )
    {
      throw .changed
    }

    let ranked = rank(
      guides,
      by: plan,
    )
    let window = PageWindow(
      total: ranked.count,
      offset: plan.offset,
      size: plan.pageSize,
    )

    return GuidePage(
      total: window.total,
      offset: window.offset,
      pageSize: window.size,
      matches: ranked[window.range].map(match),
      next: window.nextOffset.map { offset in
        token(
          moving: plan,
          to: offset,
          state: state,
        )
      },
    )
  }

  /// A digest of every guide as it reads, in order.
  private func digest(of guides: [Guide]) -> String {
    var bytes: [UInt8] = []

    for guide in guides {
      bytes += Array(guide.name.utf8)
      bytes.append(0)
      bytes += Array(guide.text.utf8)
      bytes.append(0)
    }

    return hasher.sha256Hex(of: bytes)
  }

  /// The sections that match, best first; equal scores keep the order of the guides and of the
  /// sections in each.
  private func rank(
    _ guides: [Guide],
    by plan: GuidePlan,
  ) -> [Ranked] {
    var ranked: [Ranked] = []

    for guide in guides {
      for section in guide.sections {
        let found = matcher.match(
          plan.query,
          in: [
            SearchPassage(
              weight: Self.headingWeight,
              text: section.heading,
            ),
            SearchPassage(
              weight: Self.bodyWeight,
              text: section.body,
            ),
          ],
        )

        if let found {
          ranked.append(
            Ranked(
              guide: guide.name,
              section: section,
              score: found.score,
            ),
          )
        }
      }
    }

    // `sorted` is not stable, so the place in the list breaks ties.
    return ranked.enumerated().sorted { lhs, rhs in
      lhs.element.score == rhs.element.score
        ? lhs.offset < rhs.offset
        : lhs.element.score > rhs.element.score
    }.map(\.element)
  }

  private func match(_ ranked: Ranked) -> GuideMatch {
    let text = ranked.section.body.isEmpty ? ranked.section.heading : ranked.section.body

    return GuideMatch(
      guide: ranked.guide,
      section: ranked.section.heading,
      text: SearchReason.cut(
        text.split(whereSeparator: \.isWhitespace).joined(separator: " "),
      ),
      score: Double(ranked.score) / Double(TextMatch.bestScore),
    )
  }

  private func token(
    moving plan: GuidePlan,
    to offset: Int,
    state: String,
  ) -> String {
    let next = plan.moved(to: offset)

    return codec.token(
      for: next.document(
        sealedBy: digester.seal(
          of: next.parameters,
          state: state,
        ),
      ),
    )
  }

  private struct Ranked {
    let guide: String
    let section: GuideSection
    let score: Int
  }
}
