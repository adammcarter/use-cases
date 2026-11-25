import Testing
import UseCasesCore
@testable import UseCasesCLI

struct DocsReportTests {
  private let guides = [
    Guide(
      name: "finding",
      title: "Finding use cases",
      covers: "search, and `--like`.",
      text: "# Finding use cases\n\nsearch, and `--like`.\n",
      sections: [],
    ),
    Guide(
      name: "quirks",
      title: "Quirks",
      covers: "The gotchas.",
      text: "# Quirks\n\nThe gotchas.\n",
      sections: [],
    ),
  ]

  private func page(
    total: Int,
    offset: Int = 0,
    next: String? = nil,
  ) -> GuidePage {
    GuidePage(
      total: total,
      offset: offset,
      pageSize: 1,
      matches: total == 0 ? [] : [
        GuideMatch(
          guide: "quirks",
          section: "Quirks",
          text: "The gotchas.",
          score: 0.3,
        ),
      ],
      next: next,
    )
  }

  @Test
  func `the list is a line for each guide, its name padded, then the hint`() {
    let text = DocsReport(.list(guides)).humanText(hint: true)

    #expect(text == """
    finding  search, and `--like`.
    quirks   The gotchas.

    → use-cases docs finding
    """)
  }

  @Test
  func `a guide is its text as written, with no hint`() {
    #expect(DocsReport(.guide(guides[1])).humanText(hint: true) == "# Quirks\n\nThe gotchas.\n")
  }

  @Test
  func `a page is a line for each match, how many there are, and the guide to read`() {
    let text = DocsReport(.page(page(total: 1))).humanText(hint: true)

    #expect(text == """
    quirks  Quirks  The gotchas.

    1 match
    → use-cases docs quirks
    """)
  }

  @Test
  func `a page with more to follow says where it is and gives the token`() {
    let text = DocsReport(.page(page(total: 3, offset: 1, next: "abc"))).humanText(hint: true)

    #expect(text.hasSuffix("\n\n2 of 3 matches\n→ use-cases docs --next abc"))
  }

  @Test
  func `no matches is said once, with no hint`() {
    #expect(DocsReport(.page(page(total: 0))).humanText(hint: true) == "no matches")
  }

  @Test
  func `quiet leaves the hint out of every view`() {
    #expect(!DocsReport(.list(guides)).humanText(hint: false).contains("→"))
    #expect(!DocsReport(.page(page(total: 1))).humanText(hint: false).contains("→"))
  }
}
