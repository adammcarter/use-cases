import Testing
@testable import UseCasesCore

struct UseCaseSearchErrorTests {
  @Test(arguments: [
    (UseCaseSearchError.unclosedQuote, "unclosed"),
    (.noWords, "at least one word"),
    (.likeHasNoText, "needs a use case with some text"),
    (.unknownFields(["tags"]), "--in takes id, title, description"),
    (.unknownTiers(["x"]), "--tier takes critical, core, supporting"),
    (.unknownStates([""]), "--state takes failed, error"),
    (.pageSize("0"), "--page-size is 1 to 100"),
    (.invalidToken, "--next takes a token"),
    (.changed, "changed since this search"),
  ])
  func `the refusal says what is wrong in the words the design uses`(
    error: UseCaseSearchError,
    words: String,
  ) {
    #expect(error.message.contains(words))
  }

  @Test
  func `a value that is empty is said in words`() {
    #expect(UseCaseSearchError.unknownStates([""]).message.contains("an empty value"))
  }

  @Test
  func `a filter that names nothing says so in the words of its source`() {
    let target = UseCaseTargetingError.unmatched(target: "app.nope")
    let group = GroupSelectionError.unknown(
      name: "nope",
      known: [],
    )

    #expect(UseCaseSearchError.target(target).message == target.message)
    #expect(UseCaseSearchError.group(group).message == group.message)
  }
}
