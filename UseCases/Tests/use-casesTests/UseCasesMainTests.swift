import Testing
import UseCasesCLI
@testable import use_cases

struct UseCasesMainTests {
  @Test
  func `the executable runs the use-cases command`() {
    // The built executable itself is proven by the acceptance suite run against it (ADR 037).
    #expect(UseCasesMain.command == UseCasesCommand.self)
  }
}
