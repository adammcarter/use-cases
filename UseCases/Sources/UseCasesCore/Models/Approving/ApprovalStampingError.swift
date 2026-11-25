/// Why a use case could not be signed off.
public enum ApprovalStampingError: Error, Equatable, Sendable {
  /// The promise of the use case could not be fingerprinted.
  case unfingerprintable(
    identifier: String,
    reason: String,
  )

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unfingerprintable(identifier, reason):
      "the promise of '\(identifier)' cannot be signed off: \(reason)"
    }
  }
}
