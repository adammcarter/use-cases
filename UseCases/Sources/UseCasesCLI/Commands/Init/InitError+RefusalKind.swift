import UseCasesCore

extension InitError {
  /// How a refusal to set up a folder is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .invalidPrefix:
      .usage
    case .notAFolder, .notWorkspaceRoot, .insideWorkspace, .differentPrefix, .obstructed,
         .unavailable:
      .refused
    case .invalidWorkspace:
      .invalid
    }
  }
}
