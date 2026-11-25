/// Why a JSON text could not be read. An offset counts Unicode scalars from the start of the text.
enum JSONReadingError: Error, Equatable {
  case unexpectedEnd
  case unexpectedCharacter(offset: Int)
  case invalidNumber(offset: Int)
  case integerOutOfRange(offset: Int)
  case duplicateKey(String, offset: Int)
  case invalidEscape(offset: Int)
  case controlCharacterInString(offset: Int)
  case trailingContent(offset: Int)
}
