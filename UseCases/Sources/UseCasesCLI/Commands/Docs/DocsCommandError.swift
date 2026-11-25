/// Why the words of a `docs` command line cannot be turned into a request.
enum DocsCommandError: Error, Equatable {
  /// `--next` with anything that belongs to a new search.
  case nextNotAlone

  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case .nextNotAlone:
      "--next continues a search: pass the token alone, with no words, --exact or --page-size"
    }
  }
}
