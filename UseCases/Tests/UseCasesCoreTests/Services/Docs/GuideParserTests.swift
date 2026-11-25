import Testing
@testable import UseCasesCore

struct GuideParserTests {
  private let parser = GuideParser()

  private func guide(_ text: String) throws -> Guide {
    try parser.guide(
      named: "sample",
      text: text,
    )
  }

  @Test
  func `a guide with only a lead has one section, under its title`() throws {
    let text = "# Reading status\n\nEach state, and what \"stale\" means.\n"

    let guide = try guide(text)

    #expect(guide.name == "sample")
    #expect(guide.title == "Reading status")
    #expect(guide.covers == "Each state, and what \"stale\" means.")
    #expect(guide.text == text)
    #expect(guide.sections == [
      GuideSection(
        heading: "Reading status",
        body: "Each state, and what \"stale\" means.",
      ),
    ])
  }

  @Test
  func `each second level heading starts a section that runs to the next`() throws {
    let guide = try guide(
      "# Title\n\nLead.\n\n## One\n\nfirst\n\nstill first\n\n## Two\n\nsecond\n",
    )

    #expect(guide.sections.map(\.heading) == ["Title", "One", "Two"])
    #expect(guide.sections.map(\.body) == ["Lead.", "first\n\nstill first", "second"])
  }

  @Test
  func `covers is the first paragraph alone, on one line`() throws {
    let guide = try guide("# Title\n\nFirst line\nsecond line.\n\nAnother paragraph.\n")

    #expect(guide.covers == "First line second line.")
    #expect(guide.sections.first?.body == "First line\nsecond line.\n\nAnother paragraph.")
  }

  @Test
  func `a heading inside a fenced code block is code, not a section`() throws {
    let guide = try guide("# Title\n\nLead.\n\n```text\n## not a heading\n```\n\n## Real\n\nbody\n")

    #expect(guide.sections.map(\.heading) == ["Title", "Real"])
    #expect(guide.sections.first?.body.contains("## not a heading") == true)
  }

  @Test
  func `other levels and an empty heading are text of the section they are in`() throws {
    let guide = try guide("# Title\n\nLead.\n\n### Deeper\n\n## \n\n## Real\n")

    #expect(guide.sections.map(\.heading) == ["Title", "Real"])
    #expect(guide.sections.first?.body == "Lead.\n\n### Deeper\n\n##")
    #expect(guide.sections.last?.body.isEmpty == true)
  }

  @Test
  func `windows line endings read the same as unix ones`() throws {
    let guide = try guide("# Title\r\n\r\nLead.\r\n\r\n## One\r\n\r\nbody\r\n")

    #expect(guide.title == "Title")
    #expect(guide.covers == "Lead.")
    #expect(guide.sections.map(\.body) == ["Lead.", "body"])
  }

  @Test(arguments: [
    "",
    "Title\n\nLead.\n",
    "#Title\n\nLead.\n",
    "# \n\nLead.\n",
    "\n# Title\n\nLead.\n",
  ])
  func `a page that does not begin with a titled heading is refused`(text: String) {
    #expect(throws: GuideParsingError.noTitle) {
      try guide(text)
    }
  }

  @Test(arguments: ["# Title\n", "# Title\n\n", "# Title\n\n## One\n\nbody\n"])
  func `a page with no lead paragraph is refused`(text: String) {
    #expect(throws: GuideParsingError.noLead) {
      try guide(text)
    }
  }
}
