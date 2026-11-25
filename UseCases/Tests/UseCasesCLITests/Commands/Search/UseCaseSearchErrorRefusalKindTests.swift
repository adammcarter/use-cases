import Testing
import UseCasesCore
@testable import UseCasesCLI

struct UseCaseSearchErrorRefusalKindTests {
  @Test(arguments: [
    UseCaseSearchError.unclosedQuote,
    .noWords,
    .likeHasNoText,
    .likeUnreadable("x"),
    .unknownFields(["x"]),
    .unknownTiers(["x"]),
    .unknownStates(["x"]),
    .pageSize("0"),
    .invalidToken,
    .target(.unmatched(target: "x")),
    .group(.unknown(name: "x", known: [])),
  ])
  func `a command line that is wrong is a usage error`(error: UseCaseSearchError) {
    #expect(error.refusalKind == .usage)
  }

  @Test
  func `a page of use cases that changed is refused, not a usage error`() {
    #expect(UseCaseSearchError.changed.refusalKind == .refused)
  }
}
