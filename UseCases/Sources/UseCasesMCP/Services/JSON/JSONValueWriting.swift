import MCP

/// Writes a ``Value`` as JSON text.
protocol JSONValueWriting: Sendable {
  /// One line, members in key order, slashes as they are; `nil` when it cannot be written (a
  /// number JSON has no spelling for).
  func text(of value: Value) -> String?
}
