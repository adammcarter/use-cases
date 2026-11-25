/// Why a search is refused (chapter 16 §15).
public enum UseCaseSearchError: Error, Equatable, Sendable {
  /// A quote in the words was opened and never closed.
  case unclosedQuote

  /// The words have nothing to look for: none, or only words to leave out.
  case noWords

  /// The use case `--like` was given has no text to look for.
  case likeHasNoText

  /// `--like` could not be read.
  case likeUnreadable(String)

  /// `--in` named a field there is not.
  case unknownFields([String])

  /// `--tier` named a tier there is not.
  case unknownTiers([String])

  /// `--state` named a state there is not.
  case unknownStates([String])

  /// `--page-size` is not a whole number from 1 to 100.
  case pageSize(String)

  /// `--next` is not a token `search` made.
  case invalidToken

  /// The use cases, their statuses or the group's members are not as they were when the search
  /// made the token, or the token was edited.
  case changed

  /// `--under` names nothing.
  case target(UseCaseTargetingError)

  /// `--group` names nothing.
  case group(GroupSelectionError)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case .unclosedQuote:
      "the words have an unclosed quote: close it, or leave it out"
    case .noWords:
      "a search needs at least one word to look for; a -word only leaves use cases out"
    case .likeHasNoText:
      "--like needs a use case with some text: a title, an intent, scenarios or out of scope"
    case let .likeUnreadable(reason):
      reason
    case let .unknownFields(words):
      Self.unknown(words, "--in takes", SearchField.allCases.map(\.rawValue))
    case let .unknownTiers(words):
      Self.unknown(words, "--tier takes", ValueTier.allCases.map(\.rawValue))
    case let .unknownStates(words):
      Self.unknown(words, "--state takes", VerificationStatus.allCases.map(\.rawValue))
    case let .pageSize(text):
      "--page-size is 1 to 100, not '\(text)'"
    case .invalidToken:
      "--next takes a token that a search printed; nothing else"
    case .changed:
      "use cases changed since this search; search again"
    case let .target(error):
      error.message
    case let .group(error):
      error.message
    }
  }

  private static func unknown(
    _ words: [String],
    _ takes: String,
    _ choices: [String],
  ) -> String {
    let named = words.map { word in
      word.isEmpty ? "an empty value" : "'\(word)'"
    }

    return "\(takes) \(choices.joined(separator: ", ")); not \(named.joined(separator: ", "))"
  }
}
