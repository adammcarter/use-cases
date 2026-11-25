import Testing
@testable import UseCasesCLI

struct CommandResultNotBuiltTests {
  @Test
  func `a request not built yet is exit 3 with one line on stderr and nothing on stdout`() {
    let result = CommandResult.notBuiltYet(command: "search")

    #expect(result.exitCode == 3)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == "use-cases search is not built yet\n")
  }

  @Test
  func `a hint is one line last on stderr, with its reason when it has one`() {
    let refusal = CommandResult.refusal(
      .usage,
      message: "nope",
      command: "record",
      json: false,
    )

    let plain = refusal.addingHint("use-cases status")
    let reasoned = refusal.addingHint(
      "use-cases record --interactive",
      reason: "to be asked for each",
    )

    #expect(plain.standardError == "error: nope\n→ use-cases status\n")
    #expect(reasoned
      .standardError == "error: nope\n→ use-cases record --interactive   to be asked for each\n")
    #expect(reasoned.exitCode == 2)
    #expect(reasoned.standardOutput == refusal.standardOutput)
  }
}
