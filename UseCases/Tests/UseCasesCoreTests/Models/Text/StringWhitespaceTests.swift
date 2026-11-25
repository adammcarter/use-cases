import Testing
@testable import UseCasesCore

struct StringWhitespaceTests {
  @Test(arguments: ["", " ", "\n", " \t\r\n ", "\u{A0}", "\u{2028}"])
  func `text with nothing but white space is whitespace only`(text: String) {
    #expect(text.isWhitespaceOnly)
  }

  @Test(arguments: ["a", " a ", ".", "\u{200B}"])
  func `text with a word in it is not`(text: String) {
    #expect(!text.isWhitespaceOnly)
  }

  @Test(arguments: [
    ("  a b \n", "a b"),
    ("a", "a"),
    ("", ""),
    ("   ", ""),
    ("\n\ta\u{A0}", "a"),
    (" a  b ", "a  b"),
  ])
  func `outer white space of any kind is dropped and the inside is kept`(
    text: String,
    expected: String,
  ) {
    #expect(text.withoutOuterWhitespace == expected)
  }
}
