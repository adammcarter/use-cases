/// Path-safety failures. The `code` values are frozen public contract
/// (ADR 0007 decision 8) and map to the `UCM_PATH_*` public error codes.
public enum PathError: Error, Equatable, Sendable {
  /// A path resolved outside the boundary it was required to stay within.
  case escape(String)

  /// A user-supplied identifier was not a canonical id, so it may not become
  /// a filesystem path segment or a ledger lookup key.
  case invalidIdentifier(parameterName: String, value: String)

  /// The stable wire code carried by diagnostics raised from this error.
  public var code: String {
    switch self {
    case .escape:
      "path.escape"
    case .invalidIdentifier:
      "path.invalid_id"
    }
  }

  /// The human-readable message carried alongside the code.
  public var message: String {
    switch self {
    case let .escape(message):
      message
    case let .invalidIdentifier(parameterName, value):
      "Invalid \(parameterName) '\(value)': must be a canonical id "
        + "(lowercase, no path separators, no '..')."
    }
  }
}
