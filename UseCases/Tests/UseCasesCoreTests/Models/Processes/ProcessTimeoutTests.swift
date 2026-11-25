import Testing
@testable import UseCasesCore

struct ProcessTimeoutTests {
  @Test
  func `a transformer has 120 seconds`() {
    #expect(ProcessTimeout.transformer == .seconds(120))
  }

  @Test
  func `a run command with no timeout_seconds gets 600 seconds`() {
    #expect(ProcessTimeout.runCommand(timeoutSeconds: nil) == .seconds(600))
    #expect(ProcessTimeout.runCommandDefault == .seconds(600))
  }

  @Test(arguments: [1, 900, Int.max])
  func `a run command's own timeout_seconds wins`(seconds: Int) {
    #expect(ProcessTimeout.runCommand(timeoutSeconds: seconds) == .seconds(seconds))
  }
}
