extension JSONReadingError: CustomStringConvertible {
  /// What is wrong with the text, and where when that is known (a count of Unicode scalars).
  var description: String {
    switch self {
    case .unexpectedEnd:
      "the text ends before the document does"
    case let .unexpectedCharacter(offset):
      "unexpected character at offset \(offset)"
    case let .invalidNumber(offset):
      "invalid number at offset \(offset)"
    case let .integerOutOfRange(offset):
      "integer out of range at offset \(offset)"
    case let .duplicateKey(key, offset):
      "duplicate key \(AuthoredValue.quote(key)) at offset \(offset)"
    case let .invalidEscape(offset):
      "invalid escape at offset \(offset)"
    case let .controlCharacterInString(offset):
      "control character in a string at offset \(offset)"
    case let .trailingContent(offset):
      "content after the document at offset \(offset)"
    }
  }
}
