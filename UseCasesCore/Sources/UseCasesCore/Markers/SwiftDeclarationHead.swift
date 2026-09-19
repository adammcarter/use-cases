/// Reading the declaration that follows a marker: past its attributes and
/// modifiers to the classifying keyword, and the name after it.
enum SwiftDeclarationHead {
  /// The index of the first token that is not an attached attribute
  /// (`@Name` with an optional balanced argument list), a modifier, a newline,
  /// or a `class` that modifies a following `func`.
  static func skipAttributesAndModifiers(_ tokens: [SwiftCodeToken]) -> Int {
    var index = skipAttributes(tokens)
    while index < tokens.count {
      let token = tokens[index]
      let skippable = token.kind == .newline
        || (token.kind == .word && SwiftDeclarationGrammar.modifiers.contains(token.text))
        || isClassModifyingFunction(tokens, at: index)
      guard skippable else {
        break
      }
      index += 1
    }
    return index
  }

  private static func skipAttributes(_ tokens: [SwiftCodeToken]) -> Int {
    var index = 0
    while index < tokens.count {
      if tokens[index].kind == .newline {
        index += 1
        continue
      }
      guard tokens[index].kind == .attributeSign else {
        break
      }
      index += 1
      if index < tokens.count, tokens[index].kind == .word {
        index += 1
      }
      if index < tokens.count, tokens[index].kind == .leftParenthesis {
        index = skipBalancedParentheses(tokens, from: index)
      }
    }
    return index
  }

  /// Past the parenthesis that closes the one at `start`, or the end of the
  /// tokens when it never closes.
  private static func skipBalancedParentheses(
    _ tokens: [SwiftCodeToken],
    from start: Int,
  ) -> Int {
    var depth = 0
    var index = start
    while index < tokens.count {
      if tokens[index].kind == .leftParenthesis {
        depth += 1
      } else if tokens[index].kind == .rightParenthesis {
        depth -= 1
        if depth == 0 {
          return index + 1
        }
      }
      index += 1
    }
    return index
  }

  /// `class func`: a leading `class` is a type-method modifier only when a
  /// `func` keyword follows it, newlines aside.
  private static func isClassModifyingFunction(
    _ tokens: [SwiftCodeToken],
    at index: Int,
  ) -> Bool {
    guard tokens[index].kind == .word, tokens[index].text == "class" else {
      return false
    }
    var next = index + 1
    while next < tokens.count, tokens[next].kind == .newline {
      next += 1
    }
    return next < tokens.count && tokens[next].kind == .word && tokens[next].text == "func"
  }

  /// The classifying token, which must be the `func` keyword.
  static func requireFunction(
    _ tokens: [SwiftCodeToken],
    at index: Int,
  ) throws(RecognitionFailure) -> SwiftCodeToken {
    guard index < tokens.count else {
      throw notFunction("end of file")
    }
    let head = tokens[index]
    guard head.kind == .word, head.text == "func" else {
      throw notFunction(head.text)
    }
    return head
  }

  private static func notFunction(_ found: String) -> RecognitionFailure {
    RecognitionFailure(
      .nextNodeNotFunction,
      "the declaration after the marker is not a func (\(found))",
    )
  }

  /// The name after `func`: an identifier (a following generic clause is not
  /// part of it) or an operator run such as `==`, stopping at `(`, `{` or `[`.
  static func symbolName(
    _ source: [UInt16],
    afterKeywordAt position: Int,
  ) throws(RecognitionFailure) -> String {
    var start = position + "func".utf16.count
    while start < source.count, CodeUnits.isJavaScriptWhitespace(source[start]) {
      start += 1
    }
    let rest = source[min(start, source.count)...]
    let name: ArraySlice<UInt16> = if let first = rest.first, CodeUnits.isWordStart(first) {
      rest.prefix(while: CodeUnits.isWordCharacter)
    } else {
      rest.prefix(while: isOperatorNameUnit)
    }
    guard !name.isEmpty else {
      throw RecognitionFailure(.swiftParseErrorInRegion, "could not read the function name")
    }
    return CodeUnits.string(name)
  }

  /// JavaScript's `[^\sA-Za-z0-9_({[]`.
  private static func isOperatorNameUnit(_ unit: UInt16) -> Bool {
    !CodeUnits.isJavaScriptWhitespace(unit)
      && !CodeUnits.isWordCharacter(unit)
      && unit != CodeUnits.leftParenthesis
      && unit != CodeUnits.leftCurlyBracket
      && unit != CodeUnits.leftSquareBracket
  }
}
