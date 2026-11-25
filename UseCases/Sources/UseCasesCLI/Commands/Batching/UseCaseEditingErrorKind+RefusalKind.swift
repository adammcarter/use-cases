import UseCasesCore

extension UseCaseEditingError.Kind {
  /// The `error.kind` of a refusal of this kind.
  var refusalKind: RefusalKind {
    switch self {
    case .usage:
      .usage
    case .invalid:
      .invalid
    case .refused:
      .refused
    }
  }
}
