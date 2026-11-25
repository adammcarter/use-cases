import Testing
@testable import UseCasesCore

struct ProcessConsoleTailTests {
  private func console(_ text: String) -> ProcessConsole {
    ProcessConsole(
      text: text,
      omittedByteCount: 0,
    )
  }

  @Test(arguments: [
    ("", ""),
    ("boom", "boom"),
    ("  boom \n\n", "boom"),
    ("a\nb", "a\nb"),
  ])
  func `what is short is kept whole, trimmed`(
    text: String,
    tail: String,
  ) {
    #expect(console(text).tail(limit: 300) == tail)
  }

  @Test(arguments: [0, 1, 3, 9, 10])
  func `what is long is cut to its last characters`(limit: Int) {
    let text = "0123456789"

    #expect(console(text).tail(limit: limit) == String(text.suffix(limit)))
  }

  @Test
  func `a limit is counted in characters, not bytes`() {
    #expect(console("héllo wörld").tail(limit: 5) == "wörld")
  }
}
