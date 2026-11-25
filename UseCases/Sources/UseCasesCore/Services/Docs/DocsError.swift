/// Why `docs` cannot answer (chapter 16 §16).
public enum DocsError: Error, Equatable, Sendable {
  /// The guides that ship with the build cannot be read.
  case guides(GuideLoadingError)

  /// The search is refused.
  case search(GuideSearchError)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .guides(error):
      error.message
    case let .search(error):
      error.message
    }
  }
}
