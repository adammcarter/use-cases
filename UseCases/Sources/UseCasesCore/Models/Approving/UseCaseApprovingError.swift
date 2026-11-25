/// Why use cases could not be signed off (chapter 16 §14). Every refusal is found before the
/// first byte is written.
public enum UseCaseApprovingError: Error, Equatable, Sendable {
  /// The name given with `--by` cannot be recorded.
  case approver(reason: String)

  /// Use cases were named and `--all` was given too.
  case namedAndAll

  /// No use case was named and `--all` was not given.
  case nothingAsked

  /// A use case cannot be found, or its file cannot be edited by its lines.
  case editing(UseCaseEditingError)

  /// A use case could not be signed off.
  case stamping(ApprovalStampingError)

  /// How a script is told about the refusal (chapter 16 §5).
  public var kind: UseCaseEditingError.Kind {
    switch self {
    case .approver, .namedAndAll, .nothingAsked:
      .usage
    case let .editing(error):
      error.kind
    case .stamping:
      .refused
    }
  }

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .approver(message):
      message
    case .namedAndAll:
      "approve takes the use cases to sign off or --all, not both"
    case .nothingAsked:
      "approve takes the use cases to sign off, or --all for every one; not both, and not neither"
    case let .editing(error):
      error.message
    case let .stamping(error):
      error.message
    }
  }
}
