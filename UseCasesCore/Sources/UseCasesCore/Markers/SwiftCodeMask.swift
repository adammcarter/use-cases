/// Which UTF-16 code units of a Swift source are real code.
///
/// A stack-based lexer skips line comments, nestable block comments, normal,
/// multiline and raw strings (`#"…"#`, any number of pounds), character escapes,
/// and marks interpolated code `\(…)` as code again, so brace matching runs only
/// over braces the compiler would see.
///
/// The lexer indexes UTF-16 code units, exactly as the TypeScript indexes a
/// JavaScript string. It only ever compares against ASCII, so a surrogate half
/// is inert — but the POSITIONS it reports must be the TypeScript's positions.
///
/// Every lookahead is bounds-checked: JavaScript reads past the end as
/// `undefined`, which never equals a delimiter, and that is what ``unit(at:)``
/// returns as nil. Unterminated strings and comments are normal input here.
struct SwiftCodeMask {
  /// True where the code unit at that index is code context.
  let isCode: [Bool]

  init(_ source: [UInt16]) {
    var lexer = SwiftLexer(source: source)
    lexer.run()
    isCode = lexer.mask
  }
}

private enum LexicalContext: Equatable {
  case code
  case interpolation(parenthesisDepth: Int)
  case lineComment
  case blockComment(depth: Int)
  case string(multiline: Bool, pounds: Int)
}

private struct SwiftLexer {
  let source: [UInt16]
  var mask: [Bool]
  var stack: [LexicalContext] = [.code]
  var index = 0

  init(source: [UInt16]) {
    self.source = source
    mask = Array(repeating: false, count: source.count)
  }

  mutating func run() {
    while index < source.count {
      switch stack.last ?? .code {
      case .code:
        stepCode(interpolationDepth: nil)
      case let .interpolation(depth):
        stepCode(interpolationDepth: depth)
      case .lineComment:
        stepLineComment()
      case let .blockComment(depth):
        stepBlockComment(depth: depth)
      case let .string(multiline, pounds) where pounds == 0:
        stepString(multiline: multiline)
      case let .string(multiline, pounds):
        stepRawString(multiline: multiline, pounds: pounds)
      }
    }
  }

  private func unit(at position: Int) -> UInt16? {
    position >= 0 && position < source.count ? source[position] : nil
  }

  private func isTripleQuote(at position: Int) -> Bool {
    unit(at: position) == CodeUnits.quotationMark
      && unit(at: position + 1) == CodeUnits.quotationMark
      && unit(at: position + 2) == CodeUnits.quotationMark
  }

  /// JavaScript's `src.startsWith("#".repeat(count), position)`.
  private func hasPounds(
    _ count: Int,
    at position: Int,
  ) -> Bool {
    guard position >= 0, position + count <= source.count else {
      return false
    }
    return source[position ..< position + count].allSatisfy { unit in
      unit == CodeUnits.numberSign
    }
  }

  private func poundsRun(from start: Int) -> Int {
    var end = start
    while end < source.count, source[end] == CodeUnits.numberSign {
      end += 1
    }
    return end - start
  }

  private mutating func replaceTop(_ context: LexicalContext) {
    stack[stack.count - 1] = context
  }

  private mutating func stepCode(interpolationDepth: Int?) {
    mask[index] = true
    let current = source[index]
    let next = unit(at: index + 1)
    if current == CodeUnits.solidus, next == CodeUnits.solidus {
      stack.append(.lineComment)
      index += 2
    } else if current == CodeUnits.solidus, next == CodeUnits.asterisk {
      stack.append(.blockComment(depth: 1))
      index += 2
    } else if current == CodeUnits.numberSign {
      stepPound()
    } else if current == CodeUnits.quotationMark {
      let multiline = isTripleQuote(at: index)
      stack.append(.string(multiline: multiline, pounds: 0))
      index += multiline ? 3 : 1
    } else if let interpolationDepth {
      stepInterpolationParenthesis(current, depth: interpolationDepth)
    } else {
      index += 1
    }
  }

  /// A raw string `#…#"…"#…#` opens here; any other `#` (`#if`, `#selector`)
  /// is an ordinary character.
  private mutating func stepPound() {
    let pounds = poundsRun(from: index)
    let quote = index + pounds
    guard unit(at: quote) == CodeUnits.quotationMark else {
      index += 1
      return
    }
    let multiline = isTripleQuote(at: quote)
    stack.append(.string(multiline: multiline, pounds: pounds))
    index = quote + (multiline ? 3 : 1)
  }

  /// Parentheses inside `\(…)`: the unmatched `)` returns to the owning string.
  private mutating func stepInterpolationParenthesis(
    _ current: UInt16,
    depth: Int,
  ) {
    if current == CodeUnits.leftParenthesis {
      replaceTop(.interpolation(parenthesisDepth: depth + 1))
    } else if current == CodeUnits.rightParenthesis {
      if depth == 0 {
        stack.removeLast()
      } else {
        replaceTop(.interpolation(parenthesisDepth: depth - 1))
      }
    }
    index += 1
  }

  private mutating func stepLineComment() {
    if source[index] == CodeUnits.lineFeed {
      stack.removeLast()
    }
    index += 1
  }

  private mutating func stepBlockComment(depth: Int) {
    let current = source[index]
    let next = unit(at: index + 1)
    if current == CodeUnits.solidus, next == CodeUnits.asterisk {
      replaceTop(.blockComment(depth: depth + 1))
      index += 2
    } else if current == CodeUnits.asterisk, next == CodeUnits.solidus {
      if depth - 1 == 0 {
        stack.removeLast()
      } else {
        replaceTop(.blockComment(depth: depth - 1))
      }
      index += 2
    } else {
      index += 1
    }
  }

  private mutating func stepString(multiline: Bool) {
    let current = source[index]
    if current == CodeUnits.reverseSolidus {
      if unit(at: index + 1) == CodeUnits.leftParenthesis {
        stack.append(.interpolation(parenthesisDepth: 0))
      }
      // Either `\(` or an escaped character: two code units either way.
      index += 2
    } else if !multiline {
      // A single-line string cannot span lines: a newline ends it, failing closed.
      if current == CodeUnits.quotationMark || current == CodeUnits.lineFeed {
        stack.removeLast()
      }
      index += 1
    } else if isTripleQuote(at: index) {
      stack.removeLast()
      index += 3
    } else {
      index += 1
    }
  }

  /// Inside a raw string the escape is `\` followed by the string's pounds.
  private mutating func stepRawString(
    multiline: Bool,
    pounds: Int,
  ) {
    let current = source[index]
    if current == CodeUnits.reverseSolidus, hasPounds(pounds, at: index + 1) {
      if unit(at: index + 1 + pounds) == CodeUnits.leftParenthesis {
        stack.append(.interpolation(parenthesisDepth: 0))
      }
      index += 2 + pounds
    } else if !multiline {
      if current == CodeUnits.quotationMark, hasPounds(pounds, at: index + 1) {
        stack.removeLast()
        index += 1 + pounds
      } else {
        index += 1
      }
    } else if isTripleQuote(at: index), hasPounds(pounds, at: index + 3) {
      stack.removeLast()
      index += 3 + pounds
    } else {
      index += 1
    }
  }
}
