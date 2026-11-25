import MCP

/// Reads JSON text into a ``Value`` without changing it.
protocol JSONValueReading: Sendable {
  /// `nil` when the text is not one JSON value.
  func value(of text: String) -> Value?
}
