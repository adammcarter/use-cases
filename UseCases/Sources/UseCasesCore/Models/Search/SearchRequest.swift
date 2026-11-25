/// What the command line asks of `search`.
public enum SearchRequest: Equatable, Sendable {
  /// A new search.
  case new(SearchOptions)

  /// The following page of an earlier search: its `--next` token, which carries everything else.
  case continuing(token: String)
}
