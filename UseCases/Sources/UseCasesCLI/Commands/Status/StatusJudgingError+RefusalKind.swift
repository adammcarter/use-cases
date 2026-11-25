import UseCasesCore

extension StatusJudgingError {
  /// How a refusal to judge is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .invalidWorkspace:
      .invalid
    case .storage:
      .storage
    case .fingerprint:
      .refused
    }
  }
}
