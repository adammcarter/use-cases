/// Schema-module failures. The `code` values are frozen public contract
/// (ADR 0007 decision 8) and are what a diagnostic raised from one of them
/// carries on the wire.
public enum SchemaError: Error, Equatable, Sendable {
  /// A document was not valid JSON.
  case invalidJSON(message: String)

  /// The published schema files could not be loaded or did not resolve.
  case schemasUnavailable(message: String)

  /// The stable wire code carried by diagnostics raised from this error.
  public var code: String {
    switch self {
    case .invalidJSON:
      "parse_error"
    case .schemasUnavailable:
      "schema.compile_failed"
    }
  }

  /// The human-readable message carried alongside the code.
  public var message: String {
    switch self {
    case let .invalidJSON(message), let .schemasUnavailable(message):
      message
    }
  }
}
