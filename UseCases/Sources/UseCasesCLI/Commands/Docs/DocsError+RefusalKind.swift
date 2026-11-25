import UseCasesCore

extension DocsError {
  /// How a refusal of `docs` is told to a script (chapter 16 §5): guides that changed since the
  /// search, or that this build cannot read, are refused; everything else is the command line
  /// being wrong.
  var refusalKind: RefusalKind {
    switch self {
    case .guides, .search(.changed):
      .refused
    case .search:
      .usage
    }
  }
}
