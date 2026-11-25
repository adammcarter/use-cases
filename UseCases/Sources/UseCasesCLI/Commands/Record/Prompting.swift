/// How a command talks to the person at the terminal while it runs, which a ``CommandResult``
/// cannot do: it is written only once the command is done.
protocol Prompting: Sendable {
  /// Tells the person a line, and ends it.
  func show(_ text: String) async

  /// Shows a question and waits for the line the person types.
  ///
  /// - Returns: The line without its line ending, or `nil` when the input has ended.
  func ask(_ question: String) async -> String?
}
