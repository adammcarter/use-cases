import MCP

/// One tool as the server serves it: what the host is shown, and what checks its calls.
struct ToolEntry: Sendable {
  let definition: ToolDefinition

  /// What `tools/list` shows.
  let tool: Tool

  /// Checks a call's arguments against the input schema in ``tool``.
  let checker: any ToolArgumentChecking
}
