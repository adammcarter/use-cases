import UseCasesCore

extension StorePruningError {
  /// How a refusal to prune is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .invalidWorkspace:
      .invalid
    case .unreadable:
      .storage
    }
  }
}
