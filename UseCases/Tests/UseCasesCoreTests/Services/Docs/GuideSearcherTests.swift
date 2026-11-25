import Testing
@testable import UseCasesCore

struct GuideSearcherTests {
  private let searcher = GuideSearcher()

  private func matches(
    _ words: String,
    isExact: Bool = false,
    in guides: [Guide] = GuideFixture.all,
  ) throws -> [GuideMatch] {
    try searcher.search(
      GuideFixture.plan(
        words,
        isExact: isExact,
      ),
      in: guides,
    ).matches
  }

  @Test
  func `a word finds the section it is in, whole`() throws {
    let found = try matches("stale")

    #expect(found.first == GuideMatch(
      guide: "reading-status",
      section: "Reading status",
      text: "Each state, and what \"stale\" means.",
      score: 0.3,
    ))
  }

  @Test
  func `a match in a heading counts more than one in the text`() throws {
    let found = try matches("verifying")

    #expect(found.map(\.guide) == ["verifying"])
    #expect(found.first?.score == 1.0)
  }

  @Test
  func `equal scores keep the order of the guides and of the sections in them`() throws {
    let found = try matches("stale")

    // The lead of reading-status and the Old verdicts section of quirks both hold the word in
    // the text; the guides come in the order given.
    #expect(found.map(\.guide) == ["reading-status", "quirks"])
    #expect(found.map(\.score).first == found.map(\.score).last)
    #expect(found.last?.section == "Old verdicts")

    let reversed = try matches("stale", in: GuideFixture.all.reversed())

    #expect(reversed.map(\.guide) == ["quirks", "reading-status"])
  }

  @Test
  func `typos are forgiven unless the search is exact`() throws {
    #expect(try matches("stlae").first?.guide == "reading-status")
    #expect(try matches("stlae", isExact: true).isEmpty)
  }

  @Test
  func `a phrase must appear as written and a minus word leaves a section out`() throws {
    #expect(try matches("\"need quotes\"").map(\.guide) == ["quirks"])
    #expect(try matches("\"quotes need\"").isEmpty)
    #expect(try matches("stale -verdict").map(\.guide) == ["reading-status"])
  }

  @Test
  func `nothing found is an empty page, not a refusal`() throws {
    let page = try searcher.search(
      GuideFixture.plan("spaceship"),
      in: GuideFixture.all,
    )

    #expect(page == GuidePage(
      total: 0,
      offset: 0,
      pageSize: 20,
      matches: [],
      next: nil,
    ))
  }

  @Test
  func `the text is one line, cut to 160 characters`() throws {
    let long = String(repeating: "word ", count: 60) + "\n\ntail"
    let guide = Guide(
      name: "long",
      title: "Long",
      covers: "word",
      text: "# Long\n\n" + long + "\n",
      sections: [GuideSection(heading: "Long", body: long)],
    )

    let text = try #require(matches("word", in: [guide]).first?.text)

    #expect(text.count == 160)
    #expect(!text.contains("\n"))
    #expect(text.hasPrefix("word word word"))
  }

  @Test
  func `a section with no text is shown by its heading`() throws {
    let guide = Guide(
      name: "bare",
      title: "Bare",
      covers: "Lead.",
      text: "# Bare\n\nLead.\n\n## Empty one\n",
      sections: [
        GuideSection(heading: "Bare", body: "Lead."),
        GuideSection(heading: "Empty one", body: ""),
      ],
    )

    let found = try #require(matches("empty", in: [guide]).first)

    #expect(found.section == "Empty one")
    #expect(found.text == "Empty one")
  }

  @Test
  func `pages continue from the token and add up to every match`() throws {
    let first = try searcher.search(
      GuideFixture.plan(
        "stale",
        pageSize: 1,
      ),
      in: GuideFixture.all,
    )

    #expect(first.total > 1)
    #expect(first.offset == 0)
    #expect(first.matches.count == 1)

    var pages = first.matches
    var token = first.next
    let planner = GuidePlanner()

    while let following = token {
      let page = try searcher.search(
        planner.plan(continuing: following),
        in: GuideFixture.all,
      )
      pages += page.matches
      token = page.next
    }

    #expect(try pages == matches("stale"))
    #expect(pages.count == first.total)
  }

  @Test
  func `a page after guides changed is refused`() throws {
    let first = try searcher.search(
      GuideFixture.plan(
        "stale",
        pageSize: 1,
      ),
      in: GuideFixture.all,
    )
    let plan = try GuidePlanner().plan(continuing: #require(first.next))
    var changed = GuideFixture.all
    changed[0] = Guide(
      name: changed[0].name,
      title: changed[0].title,
      covers: changed[0].covers,
      text: changed[0].text + "More.\n",
      sections: changed[0].sections,
    )

    #expect(throws: GuideSearchError.changed) {
      try searcher.search(
        plan,
        in: changed,
      )
    }
  }

  @Test
  func `the same search gives the same token`() throws {
    let plan = try GuideFixture.plan(
      "the",
      pageSize: 1,
    )

    #expect(
      try searcher.search(plan, in: GuideFixture.all).next
        == searcher.search(plan, in: GuideFixture.all).next,
    )
  }
}
