import UseCasesCore

extension UseCaseEditingError {
  /// How a refusal to save or remove is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch kind {
    case .usage:
      .usage
    case .invalid:
      .invalid
    case .refused:
      .refused
    }
  }
}
