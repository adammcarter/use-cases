import Testing
@testable import UseCasesCore

struct YAMLLiteralBlockWriterTests {
  private let writer = YAMLLiteralBlockWriter()

  private func block(
    _ text: String,
    parentIndent: Int = 0,
  ) -> YAMLLiteralBlock? {
    writer.block(
      of: text,
      parentIndent: parentIndent,
    )
  }

  // Mutant: the chomping indicator chosen from the wrong number of trailing line breaks.
  @Test(arguments: [
    ("a\nb", "|-", ["  a", "  b"]),
    ("a\nb\n", "|", ["  a", "  b"]),
    ("a\nb\n\n", "|+", ["  a", "  b", ""]),
    ("a\nb\n\n\n", "|+", ["  a", "  b", "", ""]),
    ("a\n", "|", ["  a"]),
    ("a\n\n", "|+", ["  a", ""]),
  ])
  func `the last line breaks are said by the chomping indicator`(
    text: String,
    header: String,
    lines: [String],
  ) {
    #expect(block(text) == YAMLLiteralBlock(header: header, lines: lines))
  }

  // Mutant: blank lines indented, or dropped.
  @Test
  func `a blank line inside the text is an empty line, with no spaces`() {
    #expect(block("a\n\nb") == YAMLLiteralBlock(header: "|-", lines: ["  a", "", "  b"]))
    #expect(block("\nb") == YAMLLiteralBlock(header: "|-", lines: ["", "  b"]))
    #expect(block("a\n\n\nb") == YAMLLiteralBlock(header: "|-", lines: ["  a", "", "", "  b"]))
  }

  // Mutant: the indentation indicator left out.
  @Test(arguments: [
    (" a\nb", "|2-", ["   a", "  b"]),
    ("\n a\nb", "|2-", ["", "   a", "  b"]),
    ("  a\nb\n", "|2", ["    a", "  b"]),
    (" a\nb\n\n", "|2+", ["   a", "  b", ""]),
    ("\ta\nb", "|2-", ["  \ta", "  b"]),
  ])
  func `a first line that starts with a space or a tab says how far the block is indented`(
    text: String,
    header: String,
    lines: [String],
  ) {
    #expect(block(text) == YAMLLiteralBlock(header: header, lines: lines))
  }

  @Test(arguments: ["a\n b", "a\n\tb", "a\n  \nb", "a \nb", "a\n#b", "a\n- b", "tab\n\tx"])
  func `a later line that starts with a space, a tab or a symbol needs no indicator`(
    text: String,
  ) throws {
    let found = try #require(block(text))

    #expect(found.header == "|-")
  }

  @Test(arguments: [0, 2, 6])
  func `the lines sit two spaces in from where the key or dash sits`(parentIndent: Int) throws {
    let found = try #require(block("a\nb", parentIndent: parentIndent))
    let margin = String(repeating: " ", count: parentIndent + 2)

    #expect(found.lines == [margin + "a", margin + "b"])
  }

  @Test
  func `text that is not held exactly stays in quotes: no line break, nothing to see, or escapes`()
  {
    for text in [
      "one line", "", "\n", "\n\n", " \n ", "\t\n", "a\r\nb", "a\u{0}\nb", "a\u{1}\nb",
      "a\u{7F}\nb",
      "a\u{85}\nb", "a\u{2028}\nb", "a\u{2029}\nb", "a\u{FEFF}\nb", "a\u{FFFE}\nb",
    ] {
      #expect(block(text) == nil, Comment(rawValue: text.debugDescription))
    }
  }

  @Test
  func `tabs and every other printable character are held`() throws {
    let found = try #require(block("a\tb\n日本語 😀 é\u{A0}\n"))

    #expect(found.lines == ["  a\tb", "  日本語 😀 é\u{A0}"])
  }

  @Test
  func `a line may end with spaces, which the block keeps`() throws {
    let found = try #require(block("a  \nb\n"))

    #expect(found.lines == ["  a  ", "  b"])
  }
}
