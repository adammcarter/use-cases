import UseCasesCore

extension WorkspaceLoadingError {
  /// How a refusal to load is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .noWorkspace, .invalid:
      .invalid
    case .schemasUnavailable:
      .refused
    }
  }
}
