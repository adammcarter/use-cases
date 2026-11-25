import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct SearchReportTests {
  private static func match(
    _ identifier: String,
    reasons: [SearchReason],
    status: VerificationStatus = .unverified,
  ) -> SearchMatch {
    SearchMatch(
      identifier: identifier,
      title: "Title of \(identifier)",
      file: "use-cases/x.yml",
      status: status,
      valueTier: "core",
      score: 0.5,
      reasons: reasons,
      definition: nil,
    )
  }

  private static let title = SearchReason(
    field: .title,
    location: nil,
    text: "Double tap",
  )
  private static let outOfScope = SearchReason(
    field: .outOfScope,
    location: nil,
    text: "Double tap to zoom",
  )

  private func page(
    _ matches: [SearchMatch],
    total: Int? = nil,
    offset: Int = 0,
    next: String? = nil,
  ) -> SearchReport {
    SearchReport(
      SearchPage(
        total: total ?? matches.count,
        offset: offset,
        pageSize: 20,
        matches: matches,
        next: next,
      ),
    )
  }

  @Test
  func `a match is a line of its state, id, title and strongest reason`() {
    let text = page([Self.match("a.b", reasons: [Self.title])]).humanText(hint: true)

    #expect(text == """
    ○ unverified  a.b  Title of a.b  title: "Double tap"

    1 match
    → use-cases show a.b
    """)
  }

  @Test
  func `columns line up across matches`() {
    let lines = page([
      Self.match("a.b", reasons: [Self.title]),
      Self.match("a.long.id", reasons: [Self.title], status: .verified),
    ]).humanText(hint: false).components(separatedBy: "\n")

    #expect(lines[0] == "○ unverified  a.b        Title of a.b        title: \"Double tap\"")
    #expect(lines[1] == "✓ verified    a.long.id  Title of a.long.id  title: \"Double tap\"")
    #expect(lines[3] == "2 matches")
  }

  @Test
  func `an out of scope reason that is not first is said to be one too`() {
    let also = page([Self.match("a.b", reasons: [Self.title, Self.outOfScope])])
    let first = page([Self.match("a.b", reasons: [Self.outOfScope, Self.title])])

    #expect(also.humanText(hint: false).contains("title: \"Double tap\"  (also out of scope)"))
    #expect(first.humanText(hint: false).contains("out of scope: \"Double tap to zoom\""))
    #expect(!first.humanText(hint: false).contains("also out of scope"))
  }

  @Test
  func `a scenario and a route are named`() {
    let report = page([
      Self.match("a.b", reasons: [
        SearchReason(field: .scenarios, location: "main", text: "x"),
      ]),
      Self.match("a.c", reasons: [
        SearchReason(field: .validation, location: "manual", text: "y"),
      ]),
    ])
    let text = report.humanText(hint: false)

    #expect(text.contains("scenario main: \"x\""))
    #expect(text.contains("route manual: \"y\""))
  }

  @Test
  func `a reason on several lines is told on one`() {
    let reason = SearchReason(
      field: .intent,
      location: nil,
      text: "one\ntwo  \n",
    )
    let text = page([Self.match("a.b", reasons: [reason])]).humanText(hint: false)

    #expect(text.contains("intent: \"one two\""))
  }

  @Test
  func `a page says where it is among all, and offers the next page`() {
    let text = page(
      [Self.match("a.b", reasons: [Self.title]), Self.match("a.c", reasons: [Self.title])],
      total: 5,
      offset: 2,
      next: "tok",
    ).humanText(hint: true)

    #expect(text.hasSuffix("\n\n3–4 of 5 matches\n→ use-cases search --next tok"))
  }

  @Test
  func `the last page that has one match says it by its place`() {
    let text = page(
      [Self.match("a.b", reasons: [Self.title])],
      total: 5,
      offset: 4,
    ).humanText(hint: true)

    #expect(text.contains("\n5 of 5 matches\n"))
  }

  @Test
  func `no matches is said plainly, with no hint`() {
    #expect(page([]).humanText(hint: true) == "no matches")
  }

  @Test
  func `quiet leaves out the hint`() {
    let text = page([Self.match("a.b", reasons: [Self.title])]).humanText(hint: false)

    #expect(!text.contains("→"))
  }

  @Test
  func `the document of nothing found has exactly the keys of the schema`() throws {
    let text = try page([]).jsonText()

    #expect(text == """
    {
      "command": "search",
      "matches": [],
      "next": null,
      "offset": 0,
      "output_version": 1,
      "page_size": 20,
      "total": 0
    }\n
    """)
  }

  @Test
  func `a match leaves out a tier it has none of and a place a reason has none of`() throws {
    let bare = SearchMatch(
      identifier: "a.b",
      title: "T",
      file: "f.yml",
      status: .draft,
      valueTier: nil,
      score: 1,
      reasons: [Self.title],
      definition: nil,
    )
    let text = try page([bare]).jsonText()

    #expect(!text.contains("value_tier"))
    #expect(!text.contains("where"))
    #expect(!text.contains("definition"))
    #expect(text.contains("\"score\": 1.0"))
  }
}
