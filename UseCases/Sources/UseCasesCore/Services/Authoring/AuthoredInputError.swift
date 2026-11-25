/// Why authored input could not be read.
enum AuthoredInputError: Error, Equatable, Sendable {
  /// A path that is no file: nothing is there, or a folder, a pipe or a device is. Nothing is
  /// opened.
  case notAFile(path: String)

  /// A file that is there but cannot be read.
  case unreadable(path: String, reason: String)

  /// The input is not UTF-8 text.
  case notUTF8(name: String)

  /// YAML the strict reader refuses, or text it cannot read.
  case yaml(YAMLReadingError)

  /// JSON that cannot be read, with where: `offset` counts Unicode scalars from the start.
  case json(name: String, JSONReadingError)

  /// JSON with a text, or a key, that starts with a byte order mark (U+FEFF), which YAML readers
  /// drop.
  case leadingByteOrderMark(name: String)

  /// JSON that goes past one of the limits on size.
  case limitExceeded(name: String, YAMLLimit)

  /// The refusal as the text a person reads: the input, then what is wrong with it.
  var message: String {
    switch self {
    case let .notAFile(path):
      "'\(path)' is not a file"
    case let .unreadable(path, reason):
      "'\(path)' cannot be read: \(reason)"
    case let .notUTF8(name):
      "\(name) is not valid UTF-8 text"
    case let .yaml(error):
      error.message
    case let .json(name, error):
      "\(name): not valid JSON: \(error)"
    case let .leadingByteOrderMark(name):
      "\(name): text that starts with a byte order mark (U+FEFF) is not allowed: YAML readers "
        + "drop it, so it would not be the same text everywhere; start the text with another "
        + "character"
    case let .limitExceeded(name, limit):
      "\(name): \(limit.message)"
    }
  }
}
