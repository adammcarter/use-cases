import Testing
@testable import UseCasesCLI

struct LayoutStyleTests {
  @Test
  func `a plain header is the text, and a bold one is set with the escape codes`() {
    #expect(LayoutStyle.plain.header("WHAT") == "WHAT")
    #expect(LayoutStyle.bold.header("WHAT") == "\u{1B}[1mWHAT\u{1B}[0m")
  }
}
