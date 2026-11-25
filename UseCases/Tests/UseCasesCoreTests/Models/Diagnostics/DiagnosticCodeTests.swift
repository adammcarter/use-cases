import Testing
@testable import UseCasesCore

struct DiagnosticCodeTests {
  @Test
  func `a code reads back as written`() {
    let code = DiagnosticCode("invalid-id")
    let literal: DiagnosticCode = "invalid-id"

    #expect(code.text == "invalid-id")
    #expect(code.description == "invalid-id")
    #expect(code == literal)
  }

  @Test(
    arguments: [
      ("a-b", "b-a"),
      ("invalid-id", "invalid-path"),
      ("a", "aa"),
      ("", "a"),
    ],
  )
  func `codes order by their text`(
    smaller: String,
    larger: String,
  ) {
    #expect(DiagnosticCode(smaller) < DiagnosticCode(larger))
    #expect(!(DiagnosticCode(larger) < DiagnosticCode(smaller)))
  }

  @Test
  func `equal codes hash alike`() {
    #expect(Set([DiagnosticCode("a"), DiagnosticCode("a")]).count == 1)
  }
}
