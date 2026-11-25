/// Why the tool catalogue cannot be made.
enum ToolCatalogueError: Error, Equatable {
  /// A tool's output schema could not be loaded.
  case outputSchema(tool: String, reason: OutputSchemaError)

  /// A tool's input schema cannot be used to check calls.
  case inputSchema(tool: String, reason: ToolArgumentCheckerError)
}

extension ToolCatalogueError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .outputSchema(tool, reason):
      "the output schema of \(tool): \(reason)"
    case let .inputSchema(tool, reason):
      "the input schema of \(tool): \(reason)"
    }
  }
}
