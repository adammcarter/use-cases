import UseCasesCore

extension UseCaseSearchError {
  /// How a refusal to search is told to a script (chapter 16 §5): a page of use cases that
  /// changed is refused; everything else is the command line being wrong.
  var refusalKind: RefusalKind {
    switch self {
    case .changed:
      .refused
    default:
      .usage
    }
  }
}
