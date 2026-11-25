import Testing
@testable import UseCasesCore

struct DocsErrorTests {
  @Test(arguments: [
    (DocsError.search(.pageSize("many")), "--page-size is 1 to 100, not 'many'"),
    (DocsError.search(.invalidToken), "--next takes a token that docs printed; nothing else"),
    (DocsError.search(.changed), "the guides changed since this search; search again"),
    (
      DocsError.search(.words(.noWords)),
      "docs needs at least one word to look for; a -word only leaves guides out",
    ),
    (DocsError.search(.words(.unclosedQuote)), UseCaseSearchError.unclosedQuote.message),
    (DocsError.guides(.missing("quirks")), "this build has no copy of the guide 'quirks'"),
    (DocsError.guides(.unreadable("quirks")), "the guide 'quirks' is not text"),
    (
      DocsError.guides(.invalid("quirks")),
      "the guide 'quirks' has no title, or no first paragraph saying what it covers",
    ),
  ])
  func `a refusal says what is wrong in the words of the design`(
    error: DocsError,
    message: String,
  ) {
    #expect(error.message == message)
  }
}
