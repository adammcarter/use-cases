/// Why an authored file's text was refused (chapter 09 §14).
enum YAMLReadingError: Error, Equatable, Sendable {
  /// The text is not YAML, or cannot be read as one JSON-compatible value.
  case malformed(YAMLLocation, problem: String)

  /// A second YAML document follows the first.
  case multipleDocuments(YAMLLocation)

  /// A tag (`!`) is written.
  case tagged(YAMLLocation)

  /// An alias names no anchor written before it, which includes an anchor that contains itself.
  case undefinedAlias(YAMLLocation)

  /// A mapping key is written twice; the location is the first time it was written.
  case duplicateKey(YAMLLocation, key: String)

  /// A plain scalar that must be quoted.
  case unquoted(YAMLLocation, text: String, problem: YAMLUnquotedProblem)

  /// Unquoted text followed by a comment, which YAML would read as ending the text.
  case textCutByComment(YAMLLocation, text: String, comment: String)

  /// A text that starts with a byte order mark (U+FEFF), which some readers drop.
  case leadingByteOrderMark(YAMLLocation)

  /// A mapping key that is not text.
  case unusableKey(YAMLLocation)

  /// A file that goes past one of the limits on size.
  case limitExceeded(YAMLLocation, YAMLLimit)

  var location: YAMLLocation {
    switch self {
    case let .malformed(location, _),
         let .multipleDocuments(location),
         let .tagged(location),
         let .undefinedAlias(location),
         let .duplicateKey(location, _),
         let .unquoted(location, _, _),
         let .textCutByComment(location, _, _),
         let .leadingByteOrderMark(location),
         let .unusableKey(location),
         let .limitExceeded(location, _):
      location
    }
  }

  /// The line (counting from 1) the refusal points at.
  var line: Int {
    location.line
  }

  /// The full message, which starts with the file and the line.
  var message: String {
    "\(location.file):\(location.line): \(detail)"
  }

  private static func oneLine(_ text: String) -> String {
    text.split(
      separator: "\n",
      omittingEmptySubsequences: false,
    ).joined(separator: " ")
  }

  /// What is wrong, without the file and line the full message starts with.
  var detail: String {
    switch self {
    case let .malformed(_, problem):
      "not valid YAML: \(problem)"
    case .multipleDocuments:
      "a file holds a single document, but another one starts here"
    case .tagged:
      "a tag (a value starting with '!') is not allowed; write the value plainly"
    case .undefinedAlias:
      "this alias names no anchor written before it, or an anchor that contains itself"
    case let .duplicateKey(_, key):
      "duplicate key '\(key)'"
    case let .unquoted(_, text, problem):
      "'\(text)' \(problem.message)"
    case let .textCutByComment(_, text, comment):
      "'\(Self.oneLine(text))' is followed by '\(comment)'; "
        + "quote the whole text, or put the comment on its own line"
    case .leadingByteOrderMark:
      "text that starts with a byte order mark (U+FEFF) is not allowed: YAML readers drop it, "
        + "so it would not be the same text everywhere; start the text with another character"
    case .unusableKey:
      "a mapping key must be text; this one is a list or a mapping"
    case let .limitExceeded(_, limit):
      limit.message
    }
  }
}
