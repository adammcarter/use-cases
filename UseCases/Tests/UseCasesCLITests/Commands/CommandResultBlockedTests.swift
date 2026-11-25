import Testing
@testable import UseCasesCLI

struct CommandResultBlockedTests {
  @Test
  func `a command that needs the person is done with exit 1 and nothing on stderr`() {
    let result = CommandResult.needsAttention("gate: blocked")

    #expect(result.exitCode == 1)
    #expect(result.standardOutput == "gate: blocked\n")
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `the newline that ends the output is not written twice`() {
    #expect(CommandResult.needsAttention("a\n").standardOutput == "a\n")
  }
}
