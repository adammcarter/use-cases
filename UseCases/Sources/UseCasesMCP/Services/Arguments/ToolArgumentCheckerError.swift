/// Why a tool's input schema cannot be used to check calls.
enum ToolArgumentCheckerError: Error, Equatable {
  /// The schema could not be written as JSON.
  case unwritable

  /// The core's checker refuses the schema.
  case unusable(reason: String)
}
