/// Why a piece of text is not a run id (chapter 12 §8).
enum RunIdentifierError: Error, Equatable, Sendable {
  /// It is not 32 characters long.
  case wrongLength(String)

  /// A character is not a lowercase hexadecimal digit.
  case notLowercaseHex(String)

  /// All zeros, which no run has.
  case reserved
}

extension RunIdentifierError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .wrongLength(text):
      "\(AuthoredValue.quote(text)) is not a run id: it must be 32 characters"
    case let .notLowercaseHex(text):
      "\(AuthoredValue.quote(text)) is not a run id: use lowercase hexadecimal digits"
    case .reserved:
      "the all-zero run id is reserved"
    }
  }
}
