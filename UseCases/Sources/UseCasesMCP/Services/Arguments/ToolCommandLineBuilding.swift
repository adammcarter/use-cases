import MCP

/// Turns the arguments of a call into the command line of its command (chapter 16 §2).
protocol ToolCommandLineBuilding: Sendable {
  /// - Parameters:
  ///   - tool: The tool called.
  ///   - arguments: The arguments, already checked against its input schema.
  ///   - workspace: The workspace root for a call that names none, if the server was given one.
  func commandLine(
    for tool: ToolDefinition,
    arguments: [String: Value],
    workspace: String?,
  ) throws(ToolCommandLineError) -> ToolCommandLine
}
