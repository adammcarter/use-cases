/// Why a piece of text is not an id (chapter 05).
enum IdentityError: Error, Equatable, Sendable {
  /// Nothing was written.
  case empty

  /// A namespace has a piece with nothing in it: `app..login`, `.app`, `app.`.
  case emptySegment(within: String)

  /// A scalar outside `a-z`, `0-9` and `-`, a line break included.
  case invalidCharacter(Unicode.Scalar, within: String)

  /// A segment begins with `-`.
  case leadingHyphen(within: String)

  /// A segment ends with `-`.
  case trailingHyphen(within: String)

  /// A name the bridge settings keep for themselves (chapter 10).
  case reserved(String)
}

extension IdentityError: CustomStringConvertible {
  /// The same error, naming the whole id that was being read instead of the piece that failed.
  func naming(wholeText text: String) -> IdentityError {
    switch self {
    case .empty, .reserved:
      self
    case .emptySegment:
      .emptySegment(within: text)
    case let .invalidCharacter(scalar, _):
      .invalidCharacter(scalar, within: text)
    case .leadingHyphen:
      .leadingHyphen(within: text)
    case .trailingHyphen:
      .trailingHyphen(within: text)
    }
  }

  /// The text that was refused, empty when none was written.
  var offendingText: String {
    switch self {
    case .empty:
      ""
    case let .emptySegment(text),
         let .leadingHyphen(text),
         let .trailingHyphen(text),
         let .invalidCharacter(_, text),
         let .reserved(text):
      text
    }
  }

  /// What is wrong with it, without the text itself.
  var reason: String {
    switch self {
    case .empty:
      "an id cannot be empty"
    case .emptySegment:
      "it has an empty segment between dots"
    case let .invalidCharacter(scalar, _):
      "'\(scalar.escaped(asASCII: true))' is not allowed; use lowercase a-z, 0-9 and '-'"
    case .leadingHyphen:
      "a segment cannot begin with '-'"
    case .trailingHyphen:
      "a segment cannot end with '-'"
    case .reserved:
      "the name is reserved"
    }
  }

  var description: String {
    "'\(offendingText)' is not a valid id: \(reason)"
  }
}
