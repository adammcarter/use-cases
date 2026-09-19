/// Locating a func's body: its opening brace in the token stream, then its
/// closing brace by matching code-context braces only.
enum SwiftFunctionBody {
  /// The position of the first `{` at parenthesis and bracket depth 0 after the
  /// `func` keyword. A `}` or a new declaration keyword first means the func has
  /// no body (a protocol requirement).
  static func openingBracePosition(
    _ tokens: [SwiftCodeToken],
    after headIndex: Int,
  ) throws(RecognitionFailure) -> Int {
    var depth = 0
    for token in tokens.dropFirst(headIndex + 1) {
      switch token.kind {
      case .leftParenthesis, .leftBracket:
        depth += 1
      case .rightParenthesis, .rightBracket:
        depth = depth > 0 ? depth - 1 : depth
      case .leftBrace where depth == 0:
        return token.position
      case .rightBrace where depth == 0:
        throw RecognitionFailure(
          .functionHasNoBody,
          "func has no body (no opening brace before the enclosing scope closes)",
        )
      case .word
        where depth == 0 && SwiftDeclarationGrammar.bodylessTerminators.contains(token.text):
        throw RecognitionFailure(
          .functionHasNoBody,
          "func has no body (next declaration starts before a body brace)",
        )
      default:
        continue
      }
    }
    throw RecognitionFailure(.functionHasNoBody, "func has no body")
  }

  /// The position of the brace that closes the body opened at `openPosition`.
  static func closingBracePosition(
    _ source: [UInt16],
    mask: SwiftCodeMask,
    from openPosition: Int,
  ) throws(RecognitionFailure) -> Int {
    var depth = 0
    for position in openPosition ..< source.count where mask.isCode[position] {
      if source[position] == CodeUnits.leftCurlyBracket {
        depth += 1
      } else if source[position] == CodeUnits.rightCurlyBracket {
        depth -= 1
        if depth == 0 {
          return position
        }
      }
    }
    throw RecognitionFailure(.functionBodyHasNoClosingBrace, "func body has no closing brace")
  }
}
