import UseCasesCore

extension UseCaseApprovingError {
  /// How a refusal to approve is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    kind.refusalKind
  }
}
