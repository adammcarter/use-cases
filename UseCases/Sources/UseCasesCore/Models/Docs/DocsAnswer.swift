/// What `docs` answers: one of three views.
public enum DocsAnswer: Equatable, Sendable {
  /// Every guide, in the order of the design.
  case list([Guide])

  /// One guide, whole.
  case guide(Guide)

  /// One page of the sections that match.
  case page(GuidePage)
}
