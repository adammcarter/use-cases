import Testing
@testable import UseCasesCore

struct StringUTF8BytesTests {
  @Test(arguments: [
    "",
    "plain",
    "caf\u{E9}",
    "cafe\u{301}",
    "\u{FEFF}bom",
    "\u{65E5}\u{672C}\u{1F389}",
  ])
  func `strict UTF-8 gives back exactly its scalars`(text: String) {
    let made = String(utf8Bytes: Array(text.utf8))

    #expect(made.unicodeScalars.elementsEqual(text.unicodeScalars))
  }
}
