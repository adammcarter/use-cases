/// Why the words of a `search` command line cannot be turned into a request.
enum SearchCommandError: Error, Equatable {
  /// Neither words nor `--like`.
  case needsWords

  /// Both words and `--like`.
  case wordsAndLike

  /// `--next` with anything that belongs to a new search.
  case nextNotAlone

  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case .needsWords:
      "search needs words to look for, or --like with a use case"
    case .wordsAndLike:
      "give words or --like, not both"
    case .nextNotAlone:
      "--next continues a search: pass the token alone, with no words, --like or filters"
    }
  }
}
