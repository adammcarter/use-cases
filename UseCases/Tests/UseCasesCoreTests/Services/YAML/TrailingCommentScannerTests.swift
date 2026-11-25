import Testing
@testable import UseCasesCore

struct TrailingCommentScannerTests {
  private let scanner = TrailingCommentScanner()

  @Test(arguments: [
    ("- Check medal #4 shows", "Check medal", 2, "#4 shows"),
    ("title: High contrast   # for low vision", "High contrast", 7, "# for low vision"),
    ("- one\n  two # note", "one two", 2, "# note"),
  ])
  func `text followed by a comment on its line is found`(
    text: String,
    value: String,
    start: Int,
    comment: String,
  ) {
    let finding = scanner.finding(
      afterPlainScalar: value,
      startingAt: start,
      in: YAMLSourceText(text),
    )

    guard case let .cutsText(found) = finding else {
      Issue.record("no comment was found")
      return
    }

    #expect(found.text == comment)
  }

  @Test(arguments: [
    ("- Check it.", "Check it.", 2),
    ("- Check it.\n# a note on its own line\n- two", "Check it.", 2),
    ("title: a#b", "a#b", 7),
    ("[a, b]  # after the list", "b", 4),
    ("key: value\n", "value", 5),
    ("key:   # a note after the colon\n  - x", "key", 0),
  ])
  func `nothing is found where no text is cut`(
    text: String,
    value: String,
    start: Int,
  ) {
    let finding = scanner.finding(
      afterPlainScalar: value,
      startingAt: start,
      in: YAMLSourceText(text),
    )

    #expect(finding == .noComment)
  }

  @Test
  func `text the source does not hold is lost`() {
    let finding = scanner.finding(
      afterPlainScalar: "other",
      startingAt: 0,
      in: YAMLSourceText("this"),
    )

    #expect(finding == .lost)
  }
}
