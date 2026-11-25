import MCP

/// Finds the output schema of a command's document, standing alone.
protocol OutputSchemaLoading: Sendable {
  /// The schema published in `file` (for example `cli-status.schema.json`), with every reference
  /// copied in.
  func outputSchema(file: String) throws(OutputSchemaError) -> Value
}
