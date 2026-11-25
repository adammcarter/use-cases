import MCP

/// Keeps the arguments of the calls on their way in, exactly as the host wrote them.
protocol ToolCallArgumentHolding: Actor {
  /// Keeps `arguments` and answers the key to get them back with.
  func hold(_ arguments: Value) -> String
}
