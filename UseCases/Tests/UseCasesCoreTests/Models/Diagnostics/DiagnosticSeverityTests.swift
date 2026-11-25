import Testing
@testable import UseCasesCore

struct DiagnosticSeverityTests {
  @Test
  func `an error orders before a warning`() {
    #expect(DiagnosticSeverity.error < .warning)
    #expect(!(DiagnosticSeverity.warning < .error))
  }
}
