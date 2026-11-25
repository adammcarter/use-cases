/// Why a workspace could not be judged (chapter 16 §5).
public enum StatusJudgingError: Error, Equatable, Sendable {
  /// Fingerprinting found that the workspace is INVALID: a resource, or a link problem. Each
  /// problem is one line, in report order.
  case invalidWorkspace(problems: [String])

  /// The results store cannot be read safely (chapter 12 §24). Each problem is one line, naming
  /// the place that is wrong; nothing is inferred from damaged history.
  case storage(problems: [String])

  /// A fingerprint could not be read where it was needed: a route of a READY use case has none,
  /// or a promise could not be fingerprinted.
  case fingerprint(String)

  /// The refusal as the text a person reads: one line per problem.
  public var message: String {
    switch self {
    case let .invalidWorkspace(problems), let .storage(problems):
      problems.joined(separator: "\n")
    case let .fingerprint(message):
      message
    }
  }
}
