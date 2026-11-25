import Testing
@testable import UseCasesTransformers

struct StringLinesTests {
  @Test(arguments: [
    ("", [""]),
    ("a", ["a"]),
    ("a\n", ["a", ""]),
    ("a\nb", ["a", "b"]),
    ("a\r\nb", ["a\r", "b"]),
    ("\n\n", ["", "", ""]),
    ("é\n日本", ["é", "日本"]),
  ])
  func `source lines split at line feeds only`(
    text: String,
    expected: [String],
  ) {
    #expect(text.sourceLines == expected)
  }

  @Test(arguments: [
    ("a\nb\n", ["a", "b", ""]),
    ("a\r\nb\r\n", ["a", "b", ""]),
    ("a\r\r\n", ["a\r"]),
    ("a\rb", ["a\rb"]),
    ("a\n\nb", ["a", "", "b"]),
    ("", [""]),
  ])
  func `report lines split at line feeds, dropping one carriage return from each`(
    text: String,
    expected: [String],
  ) {
    #expect(text.reportLines.prefix(expected.count) == expected[...])
  }

  @Test(arguments: ["\u{2028}", "\u{2029}", "\u{85}", "\u{B}", "\u{C}", "\r"])
  func `no other separator ends a report line, as they are legal inside a JSON string`(
    separator: String,
  ) {
    let line = "[\"one\(separator)two\"]"

    #expect("\(line)\nnext".reportLines == [line, "next"])
  }

  @Test(arguments: [("a", "b", true), ("b", "a", false), ("a", "a", false), ("Z", "a", true)])
  func `code point order puts capitals before lower case`(
    first: String,
    second: String,
    expected: Bool,
  ) {
    #expect(first.precedesByCodePoint(second) == expected)
  }
}
