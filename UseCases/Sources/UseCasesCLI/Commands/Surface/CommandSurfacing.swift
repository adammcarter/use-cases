/// Answers a command line that is about the command list rather than a command (chapter 16 §2,
/// §7), before any command reads it.
protocol CommandSurfacing: Sendable {
  /// The answer to the command line, or `nil` when a built command reads it.
  func answer(to arguments: [String]) -> CommandResult?
}
