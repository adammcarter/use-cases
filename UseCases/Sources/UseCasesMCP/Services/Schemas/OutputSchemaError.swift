/// Why an output schema could not be loaded.
enum OutputSchemaError: Error, Equatable {
  /// The build holds no copy of the schema.
  case missing(file: String)

  /// A copy is not JSON.
  case unreadable(file: String)

  /// The references of the schema could not all be copied in.
  case notStandalone(file: String, reason: SchemaInliningError)
}

extension OutputSchemaError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .missing(file):
      "the build holds no copy of \(file)"
    case let .unreadable(file):
      "\(file) is not JSON"
    case let .notStandalone(file, reason):
      "\(file) cannot be made to stand alone: \(reason)"
    }
  }
}
