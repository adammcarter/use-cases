import UseCasesCore

extension LayoutRenderingError {
  /// How a refusal to draw a layout is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case let .status(error):
      error.refusalKind
    default:
      kind.refusalKind
    }
  }
}
