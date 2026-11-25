import MCP

/// Runs the command a tool call names and gives back its result.
protocol ToolCalling: Sendable {
  /// A call that cannot be run as asked (a missing, unknown or mistyped argument, a command that
  /// could not be started) is a result marked as a tool error. Cancelling the calling task stops
  /// the command.
  func call(_ parameters: CallTool.Parameters) async throws(ToolCallError) -> CallTool.Result
}
