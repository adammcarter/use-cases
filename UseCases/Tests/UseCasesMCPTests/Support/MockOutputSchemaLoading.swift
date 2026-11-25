import MCP
@testable import UseCasesMCP

/// Output schemas that are the same small object schema for every file, or none at all.
struct MockOutputSchemaLoading: OutputSchemaLoading {
  private let failure: OutputSchemaError?

  /// Every file has a schema.
  init() {
    failure = nil
  }

  /// Every file is refused with `error`.
  init(refusing error: OutputSchemaError) {
    failure = error
  }

  func outputSchema(file: String) throws(OutputSchemaError) -> Value {
    if let failure {
      throw failure
    }

    return .object([
      "type": .string("object"),
      "title": .string(file),
    ])
  }
}
