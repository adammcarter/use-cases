/// Why a target names nothing (chapter 16 §9).
public enum UseCaseTargetingError: Error, Equatable, Sendable {
  /// The target is neither a use case id nor the start of any.
  case unmatched(target: String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unmatched(target):
      "no use case or id prefix '\(target)' in this workspace"
    }
  }
}
