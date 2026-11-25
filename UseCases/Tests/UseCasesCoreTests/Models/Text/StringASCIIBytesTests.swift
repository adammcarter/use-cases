import Testing
@testable import UseCasesCore

struct StringASCIIBytesTests {
  @Test(arguments: ["", "a", "app.login#submit-1", "a#b.c"])
  func `ASCII bytes give the same text`(text: String) {
    #expect(String(asciiBytes: ArraySlice(text.utf8)) == text)
  }

  @Test
  func `a slice of a longer array gives only the slice`() {
    let bytes = Array("xx\(MarkerText.sentinel)a#b".utf8)

    #expect(String(asciiBytes: bytes[12...]) == "a#b")
  }
}
