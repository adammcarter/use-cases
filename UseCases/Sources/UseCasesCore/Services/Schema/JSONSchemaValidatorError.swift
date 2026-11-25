/// Why a schema cannot be used to check documents.
public enum JSONSchemaValidatorError: Error, Equatable, Sendable {
  /// The schema text is not JSON.
  case notJSON(reason: String)

  /// The schema is JSON but not one the checker can run: a keyword it does not support, a
  /// reference it cannot follow.
  case notASchema(reason: String)
}
