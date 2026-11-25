/// Tells whether a stream of the process goes to a person's terminal.
protocol TerminalChecking: Sendable {
  /// Whether the file descriptor is a terminal.
  func isTerminal(descriptor: Int32) -> Bool
}
