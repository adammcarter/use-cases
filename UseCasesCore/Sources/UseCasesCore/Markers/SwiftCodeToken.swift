/// The structural tokens the recognizer reasons over.
enum SwiftCodeTokenKind: Equatable {
  case word
  case leftBrace
  case rightBrace
  case leftParenthesis
  case rightParenthesis
  case leftBracket
  case rightBracket
  /// `@`, which opens an attribute.
  case attributeSign
  case newline
}

struct SwiftCodeToken: Equatable {
  let kind: SwiftCodeTokenKind
  /// The word itself, the punctuation character, or `\n`.
  let text: String
  /// UTF-16 position of the token's first code unit.
  let position: Int
}

/// Words and structural punctuation from the code-context units in a range.
///
/// Strings and comments are skipped via the mask, but EVERY line feed is
/// emitted — even one inside a string — because that is what the TypeScript
/// does and statement boundaries are read from it.
enum SwiftCodeTokenizer {
  private static let punctuation: [UInt16: SwiftCodeTokenKind] = [
    CodeUnits.leftCurlyBracket: .leftBrace,
    CodeUnits.rightCurlyBracket: .rightBrace,
    CodeUnits.leftParenthesis: .leftParenthesis,
    CodeUnits.rightParenthesis: .rightParenthesis,
    CodeUnits.leftSquareBracket: .leftBracket,
    CodeUnits.rightSquareBracket: .rightBracket,
    CodeUnits.commercialAt: .attributeSign,
  ]

  static func tokenize(
    _ source: [UInt16],
    mask: SwiftCodeMask,
    from start: Int,
    to limit: Int,
  ) -> [SwiftCodeToken] {
    var tokens: [SwiftCodeToken] = []
    var index = max(0, start)
    let end = min(limit, source.count)
    while index < end {
      let current = source[index]
      if current == CodeUnits.lineFeed {
        tokens.append(SwiftCodeToken(kind: .newline, text: "\n", position: index))
        index += 1
        continue
      }
      guard mask.isCode[index] else {
        index += 1
        continue
      }
      if CodeUnits.isWordStart(current) {
        var wordEnd = index + 1
        while wordEnd < end, CodeUnits.isWordCharacter(source[wordEnd]) {
          wordEnd += 1
        }
        let word = CodeUnits.string(source[index ..< wordEnd])
        tokens.append(SwiftCodeToken(kind: .word, text: word, position: index))
        index = wordEnd
        continue
      }
      if let kind = punctuation[current] {
        tokens.append(SwiftCodeToken(
          kind: kind,
          text: CodeUnits.string([current]),
          position: index,
        ))
      }
      index += 1
    }
    return tokens
  }
}
