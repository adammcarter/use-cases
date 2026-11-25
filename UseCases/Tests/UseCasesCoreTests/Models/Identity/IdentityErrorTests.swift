import Testing
@testable import UseCasesCore

struct IdentityErrorTests {
  @Test(
    arguments: [
      (IdentityError.empty, "", "an id cannot be empty"),
      (.emptySegment(within: "a..b"), "a..b", "empty segment"),
      (.invalidCharacter("L", within: "Login"), "Login", "'L' is not allowed"),
      (.invalidCharacter("\n", within: "a\n"), "a\n", "'\\n' is not allowed"),
      (.leadingHyphen(within: "-a"), "-a", "cannot begin with '-'"),
      (.trailingHyphen(within: "a-"), "a-", "cannot end with '-'"),
      (.reserved("record"), "record", "reserved"),
    ],
  )
  func `an error names the text and says what is wrong with it`(
    error: IdentityError,
    text: String,
    fragment: String,
  ) {
    #expect(error.offendingText == text)
    #expect(error.reason.contains(fragment))
    #expect(error.description == "'\(text)' is not a valid id: \(error.reason)")
  }

  @Test(
    arguments: [
      IdentityError.emptySegment(within: "piece"),
      .invalidCharacter("L", within: "piece"),
      .leadingHyphen(within: "piece"),
      .trailingHyphen(within: "piece"),
    ],
  )
  func `an error can name the whole id instead of the piece`(error: IdentityError) {
    #expect(error.naming(wholeText: "whole.piece").offendingText == "whole.piece")
  }

  @Test(arguments: [IdentityError.empty, .reserved("record")])
  func `an error with no piece to rename stays as it is`(error: IdentityError) {
    #expect(error.naming(wholeText: "whole.piece") == error)
  }
}
