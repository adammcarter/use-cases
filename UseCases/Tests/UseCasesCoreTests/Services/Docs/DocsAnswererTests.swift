import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct DocsAnswererTests {
  private let answerer = DocsAnswerer(
    loader: MockGuideLoading(guides: GuideFixture.all),
    planner: GuidePlanner(),
    searcher: GuideSearcher(),
  )

  @Test
  func `no words is the list of every guide`() throws {
    #expect(try answerer.answer(.list) == .list(GuideFixture.all))
  }

  @Test(arguments: ["quirks", " quirks ", "quirks "])
  func `a guide's exact name shows that guide`(words: String) throws {
    let answer = try answerer.answer(
      .words(
        words,
        isExact: false,
        pageSize: nil,
      ),
    )

    #expect(answer == .guide(GuideFixture.quirks))
  }

  @Test(arguments: ["Quirks", "quirk", "quirks verifying", "\"quirks\""])
  func `anything but a guide's exact name is a search`(words: String) throws {
    let answer = try answerer.answer(
      .words(
        words,
        isExact: false,
        pageSize: nil,
      ),
    )

    guard case .page = answer else {
      Issue.record("not a search: \(answer)")
      return
    }
  }

  @Test
  func `words are searched for in the guides`() throws {
    let answer = try answerer.answer(
      .words(
        "stale",
        isExact: false,
        pageSize: nil,
      ),
    )

    guard case let .page(page) = answer else {
      Issue.record("not a search: \(answer)")
      return
    }

    #expect(page.matches.map(\.guide) == ["reading-status", "quirks"])
  }

  @Test
  func `a token continues the search it came from`() throws {
    let first = try answerer.answer(
      .words(
        "stale",
        isExact: false,
        pageSize: "1",
      ),
    )
    guard case let .page(page) = first, let token = page.next else {
      Issue.record("no next page: \(first)")
      return
    }

    let second = try answerer.answer(.continuing(token: token))

    guard case let .page(following) = second else {
      Issue.record("not a search: \(second)")
      return
    }

    #expect(following.offset == 1)
    #expect(following.matches.map(\.guide) == ["quirks"])
    #expect(following.next == nil)
  }

  @Test
  func `a request that cannot be searched is refused as the search`() {
    #expect(throws: DocsError.search(.pageSize("0"))) {
      try answerer.answer(
        .words(
          "stale",
          isExact: false,
          pageSize: "0",
        ),
      )
    }
    #expect(throws: DocsError.search(.words(.noWords))) {
      try answerer.answer(
        .words(
          "-stale",
          isExact: false,
          pageSize: nil,
        ),
      )
    }
    #expect(throws: DocsError.search(.invalidToken)) {
      try answerer.answer(.continuing(token: "garbage"))
    }
  }

  @Test
  func `guides that cannot be read are refused, whatever is asked`() {
    let answerer = DocsAnswerer(
      loader: MockGuideLoading(failing: .missing("quirks")),
      planner: GuidePlanner(),
      searcher: GuideSearcher(),
    )

    #expect(throws: DocsError.guides(.missing("quirks"))) {
      try answerer.answer(.list)
    }
    #expect(throws: DocsError.guides(.missing("quirks"))) {
      try answerer.answer(
        .words(
          "stale",
          isExact: false,
          pageSize: nil,
        ),
      )
    }
  }
}
