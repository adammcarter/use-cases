import Testing
@testable import UseCasesCLI

struct InitChoiceTests {
  private static let words = ["commit", "push", "both", "none"]

  @Test(arguments: [
    ("commit", "commit"),
    ("none", "none"),
    ("1", "commit"),
    ("4", "none"),
    ("c", "commit"),
    ("pu", "push"),
    ("n", "none"),
    ("bo", "both"),
  ])
  func `an answer names a word by the word, its number or an unambiguous start`(
    answer: String,
    word: String,
  ) {
    #expect(InitChoice.word(for: answer, among: Self.words) == word)
  }

  @Test(arguments: ["", "0", "5", "-1", "01x", "x", "co mmit", "Commit", "commits", "٣"])
  func `an answer that names nothing names no word`(answer: String) {
    #expect(InitChoice.word(for: answer, among: Self.words) == nil)
  }

  @Test
  func `a start that begins several words names none of them`() {
    #expect(InitChoice.word(for: "p", among: ["push", "pull"]) == nil)
  }

  @Test
  func `an exact word wins over a number and a number over a start`() {
    #expect(InitChoice.word(for: "2", among: ["1", "2", "3"]) == "2")
    #expect(InitChoice.word(for: "1", among: ["x", "1"]) == "1")
    #expect(InitChoice.word(for: "1", among: ["one", "two"]) == "one")
    #expect(InitChoice.word(for: "t", among: ["one", "two"]) == "two")
  }
}
