import UseCasesCore

/// A layout, drawn: the model any view can draw again, and the plain text the core draws from it.
enum RenderedLayout: Equatable {
  case intent(IntentLayout)
  case brief(BriefLayout)
  case proposal(ProposalLayout)
  case results(ResultsLayout)

  var kind: RenderKind {
    switch self {
    case .intent:
      .intent
    case .brief:
      .brief
    case .proposal:
      .proposal
    case .results:
      .results
    }
  }

  /// The plain layout of the contract, its headers set in the style.
  func text(style: LayoutStyle) -> String {
    switch self {
    case let .intent(layout):
      layout.text(style: style)
    case let .brief(layout):
      layout.text(style: style)
    case let .proposal(layout):
      layout.text(style: style)
    case let .results(layout):
      layout.text(style: style)
    }
  }
}
