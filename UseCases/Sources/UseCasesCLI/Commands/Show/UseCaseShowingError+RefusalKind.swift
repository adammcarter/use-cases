import UseCasesCore

extension UseCaseShowingError {
  /// How a refusal to show is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .unknown:
      .usage
    case .unfingerprintable:
      .refused
    }
  }
}
