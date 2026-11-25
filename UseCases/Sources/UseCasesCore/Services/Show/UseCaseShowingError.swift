/// Why a use case cannot be shown (chapter 16 §14).
public enum UseCaseShowingError: Error, Equatable, Sendable {
  /// The workspace has no use case with exactly this id.
  case unknown(identifier: String)

  /// The use case's promise could not be fingerprinted, so whether it is signed off is unknown.
  case unfingerprintable(identifier: String, reason: String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unknown(identifier):
      "no use case '\(identifier)' in this workspace; show takes a use case's full id"
    case let .unfingerprintable(identifier, reason):
      "the promise of \(identifier) could not be fingerprinted: \(reason)"
    }
  }
}
