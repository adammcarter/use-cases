import Testing
@testable import UseCasesCLI

/// A command the Swift CLI does not run yet refuses honestly: a non-zero exit
/// and an error envelope saying so, never a fake success and never the unknown
/// command help.
struct NotYetPortedTests {
  static var unportedCommands: [[String]] {
    CommandRegistry.allCommands.filter { !$0.isPorted }.map(\.path)
  }

  @Test(arguments: unportedCommands)
  func `refuses an unported command with a non-zero exit`(path: [String]) async {
    let outcome = await CommandLineInterface.run(arguments: path + ["--json"])

    #expect(outcome.exitCode == 1)
    #expect(outcome.standardError.isEmpty)
    #expect(outcome.standardOutput.contains(#""ok":false"#))
    #expect(outcome.standardOutput.contains(#""code":"cli_not_yet_ported""#))
    #expect(outcome.standardOutput.hasSuffix("\n"))
  }

  @Test
  func `names the command in the human rendering`() async {
    let outcome = await CommandLineInterface.run(arguments: ["plan", "cards"])

    #expect(outcome.exitCode == 1)
    #expect(outcome.standardOutput.contains("plan cards"))
    #expect(outcome.standardOutput.hasPrefix("\u{2717} plan.cards"))
  }
}
