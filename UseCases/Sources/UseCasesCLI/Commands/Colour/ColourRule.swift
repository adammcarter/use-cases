import Foundation

/// When a command may colour or embolden what it prints (chapter 16 §19): only when the
/// standard output is a terminal, and never when `NO_COLOR` is set to something.
struct ColourRule: Equatable {
  /// Whether colour may be used.
  let allowsColour: Bool

  /// - Parameters:
  ///   - standardOutputIsTerminal: Whether what is printed goes to a person's terminal.
  ///   - environment: The environment variables of the process.
  init(
    standardOutputIsTerminal: Bool,
    environment: [String: String],
  ) {
    allowsColour = standardOutputIsTerminal && (environment["NO_COLOR"] ?? "").isEmpty
  }

  /// The rule for this process: it is the standard output that must be a terminal, whatever the
  /// standard input is.
  ///
  /// - Parameters:
  ///   - terminal: Tells which streams are terminals.
  ///   - environment: The environment variables of the process.
  init(
    terminal: any TerminalChecking,
    environment: [String: String],
  ) {
    self.init(
      standardOutputIsTerminal: terminal.isTerminal(descriptor: STDOUT_FILENO),
      environment: environment,
    )
  }
}
