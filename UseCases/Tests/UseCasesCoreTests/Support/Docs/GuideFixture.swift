@testable import UseCasesCore

/// Guides to search, written the way the bundled ones are.
enum GuideFixture {
  static let status = Guide(
    name: "reading-status",
    title: "Reading status",
    covers: "Each state, and what \"stale\" means.",
    text: "# Reading status\n\nEach state, and what \"stale\" means.\n",
    sections: [
      GuideSection(
        heading: "Reading status",
        body: "Each state, and what \"stale\" means.",
      ),
    ],
  )

  static let quirks = Guide(
    name: "quirks",
    title: "Quirks",
    covers: "The gotchas: YAML values that need quotes.",
    text: "# Quirks\n\nThe gotchas: YAML values that need quotes.\n\n## Old verdicts\n\nA stale "
      + "verdict is not a failure.\n",
    sections: [
      GuideSection(
        heading: "Quirks",
        body: "The gotchas: YAML values that need quotes.",
      ),
      GuideSection(
        heading: "Old verdicts",
        body: "A stale verdict is not a failure.",
      ),
    ],
  )

  static let verifying = Guide(
    name: "verifying",
    title: "Verifying",
    covers: "Get verdicts from tests.",
    text: "# Verifying\n\nGet verdicts from tests.\n",
    sections: [
      GuideSection(
        heading: "Verifying",
        body: "Get verdicts from tests.",
      ),
    ],
  )

  static let all = [status, quirks, verifying]

  /// A plan for a new search of `words`.
  static func plan(
    _ words: String,
    isExact: Bool = false,
    pageSize: Int = 20,
    offset: Int = 0,
  ) throws -> GuidePlan {
    try GuidePlan(
      query: SearchQueryParser().query(
        from: words,
        isExact: isExact,
      ),
      pageSize: pageSize,
      offset: offset,
      seal: nil,
    )
  }
}
