import Testing
@testable import UseCasesCLI

struct ColourRuleTests {
  /// A process whose descriptors are terminals as the test says.
  private struct StubTerminal: TerminalChecking {
    let terminals: Set<Int32>

    func isTerminal(descriptor: Int32) -> Bool {
      terminals.contains(descriptor)
    }
  }

  @Test(arguments: [
    (true, [String: String](), true),
    (false, [:], false),
    (true, ["NO_COLOR": "1"], false),
    (true, ["NO_COLOR": "anything"], false),
    (true, ["NO_COLOR": ""], true),
    (false, ["NO_COLOR": "1"], false),
    (true, ["TERM": "xterm-256color"], true),
  ])
  func `colour is for a terminal, and never when NO_COLOR is set to something`(
    isTerminal: Bool,
    environment: [String: String],
    allowed: Bool,
  ) {
    let rule = ColourRule(
      standardOutputIsTerminal: isTerminal,
      environment: environment,
    )

    #expect(rule.allowsColour == allowed)
  }

  // Lists, not sets: a set's order changes from run to run, and so would each case's name.
  @Test(arguments: [
    ([1] as [Int32], true),
    ([0, 1, 2], true),
    ([0], false),
    ([0, 2], false),
    ([], false),
  ])
  func `colour follows the standard output's terminal, never the standard input's`(
    terminals: [Int32],
    allowed: Bool,
  ) {
    let rule = ColourRule(
      terminal: StubTerminal(terminals: Set(terminals)),
      environment: [:],
    )

    #expect(rule.allowsColour == allowed)
  }

  @Test
  func `no colour with NO_COLOR set, even at a terminal`() {
    let rule = ColourRule(
      terminal: StubTerminal(terminals: [0, 1, 2]),
      environment: ["NO_COLOR": "1"],
    )

    #expect(!rule.allowsColour)
  }
}
