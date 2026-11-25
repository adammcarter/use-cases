import UseCasesCore

extension UseCaseBatchError {
  /// How a refusal to apply a batch is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    kind.refusalKind
  }
}
