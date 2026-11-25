import Testing
@testable import UseCasesCore

struct StringLooseComparisonTests {
  @Test(
    arguments: [
      ("specs", "specs"),
      ("specs", "Specs"),
      ("USE-CASES", "use-cases"),
      ("caf\u{E9}", "cafe\u{301}"),
      ("CAF\u{C9}", "cafe\u{301}"),
    ],
  )
  func `names that differ only in case or Unicode form are loosely equal`(
    left: String,
    right: String,
  ) {
    #expect(left.isLooselyEqual(to: right))
    #expect(right.isLooselyEqual(to: left))
  }

  @Test(arguments: [("specs", "spec"), ("specs", "specs "), ("a", "b"), ("", "a"), ("use", "user")])
  func `names that differ in anything else are not loosely equal`(
    left: String,
    right: String,
  ) {
    #expect(!left.isLooselyEqual(to: right))
  }
}
