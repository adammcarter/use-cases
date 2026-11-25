/// Why a search of the guides is refused (chapter 16 §16).
public enum GuideSearchError: Error, Equatable, Sendable {
  /// The words typed cannot be searched for: a quote never closed, or nothing to look for.
  case words(UseCaseSearchError)

  /// `--page-size` is not a whole number from 1 to 100.
  case pageSize(String)

  /// `--next` is not a token `docs` made.
  case invalidToken

  /// The guides are not as they were when the search made the token, or the token was edited.
  case changed

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case .words(.noWords):
      "docs needs at least one word to look for; a -word only leaves guides out"
    case let .words(error):
      error.message
    case let .pageSize(text):
      "--page-size is 1 to 100, not '\(text)'"
    case .invalidToken:
      "--next takes a token that docs printed; nothing else"
    case .changed:
      "the guides changed since this search; search again"
    }
  }
}
