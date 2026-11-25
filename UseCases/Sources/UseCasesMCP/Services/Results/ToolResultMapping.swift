import MCP
import UseCasesCore

/// Turns what a command printed into the result of its tool call (chapter 20 §4).
protocol ToolResultMapping: Sendable {
  /// - Parameters:
  ///   - outcome: How the command ended and what it printed.
  ///   - command: The command's name.
  func result(
    for outcome: CommandOutcome,
    command: String,
  ) -> CallTool.Result

  /// The result of a call the server refuses before running anything.
  func refusal(_ document: ToolErrorDocument) -> CallTool.Result
}
