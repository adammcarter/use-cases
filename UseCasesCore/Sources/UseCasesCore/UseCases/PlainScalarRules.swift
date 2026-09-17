/// The pattern tests `yaml`'s `stringifyString` runs to decide whether a string
/// may be written plain. Each is a JavaScript regular expression in the
/// original; they are spelled out over UTF-16 code units here because a Swift
/// regex's `$` also matches before a trailing line separator, and JavaScript's
/// does not.
enum PlainScalarRules {
  /// `/^[\n\t ,[\]{}#&*!|>'"%@`]|^[?-]$|^[?-][ \t]|[\n:][ \t]|[ \t]\n|[\n\t ]#|[\n\t :]$/`:
  /// an indicator first, a lone or spaced `?`/`-`, `: ` or a newline before a
  /// blank, a blank before a newline, a `#` after a blank, or a blank or `:`
  /// last.
  static func needsQuoting(_ text: [UInt16]) -> Bool {
    guard let first = text.first, let last = text.last else {
      return false
    }
    if leadingIndicators.contains(first) {
      return true
    }
    if first == CodeUnits.questionMark || first == CodeUnits.hyphenMinus {
      if text.count == 1 || CodeUnits.isSpaceOrTab(text[1]) {
        return true
      }
    }
    for index in text.indices.dropLast() {
      let current = text[index]
      let next = text[index + 1]
      if current == CodeUnits.lineFeed || current == CodeUnits.colon, CodeUnits.isSpaceOrTab(next) {
        return true
      }
      if CodeUnits.isSpaceOrTab(current), next == CodeUnits.lineFeed {
        return true
      }
      if current == CodeUnits.lineFeed || CodeUnits.isSpaceOrTab(current),
         next == CodeUnits.numberSign
      {
        return true
      }
    }
    return last == CodeUnits.lineFeed || last == CodeUnits.colon || CodeUnits.isSpaceOrTab(last)
  }

  /// `/^(%|---|\.\.\.)/`, for text holding no line feed.
  static func startsWithDocumentMarker(_ text: [UInt16]) -> Bool {
    text.first == CodeUnits.percentSign
      || text.starts(with: Array("---".utf16))
      || text.starts(with: Array("...".utf16))
  }

  /// `/\n[\t ]+$/`: a last line holding only blanks.
  static func endsWithIndentedEmptyLine(_ text: [UInt16]) -> Bool {
    var index = text.count
    while index > 0, CodeUnits.isSpaceOrTab(text[index - 1]) {
      index -= 1
    }
    return index < text.count && index > 0 && text[index - 1] == CodeUnits.lineFeed
  }

  /// True when the YAML 1.2 core schema would read the text back as something
  /// other than a string: the `test` of the `null`, `bool`, `int` (octal,
  /// decimal, hexadecimal) and `float` (special, exponent, fixed) tags.
  static func resolvesToNonString(_ text: [UInt16]) -> Bool {
    let spelled = CodeUnits.string(text)
    if nullSpellings.contains(spelled) || boolSpellings.contains(spelled) || specialFloatSpellings
      .contains(spelled)
    {
      return true
    }
    if isPrefixed(text, "0o", digits: isOctalDigit) || isPrefixed(
      text,
      "0x",
      digits: isHexadecimalDigit,
    ) {
      return true
    }
    var scanner = Scanner(text)
    scanner.skipSign()
    let integerDigits = scanner.skipDigits()
    if scanner.isAtEnd {
      return integerDigits > 0
    }
    var fractionDigits = 0
    var hasPoint = false
    if scanner.skip(CodeUnits.fullStop) {
      hasPoint = true
      fractionDigits = scanner.skipDigits()
    }
    let mantissaIsValid = integerDigits > 0 || (hasPoint && fractionDigits > 0)
    if scanner.isAtEnd {
      return hasPoint && mantissaIsValid
    }
    guard mantissaIsValid, scanner.skip(0x65) || scanner.skip(0x45) else {
      return false
    }
    scanner.skipSign()
    return scanner.skipDigits() > 0 && scanner.isAtEnd
  }

  private static let leadingIndicators: Set<UInt16> = Set("\n\t ,[]{}#&*!|>'\"%@`".utf16)
  private static let nullSpellings: Set<String> = ["", "~", "null", "Null", "NULL"]
  private static let boolSpellings: Set<String> = [
    "true",
    "True",
    "TRUE",
    "false",
    "False",
    "FALSE",
  ]
  private static let specialFloatSpellings: Set<String> = [
    ".inf", ".Inf", ".INF", "-.inf", "-.Inf", "-.INF", "+.inf", "+.Inf", "+.INF", ".nan", ".NaN",
    ".NAN",
  ]

  private static func isPrefixed(
    _ text: [UInt16],
    _ prefix: String,
    digits: (UInt16) -> Bool,
  ) -> Bool {
    let prefixUnits = Array(prefix.utf16)
    return text.count > prefixUnits.count && text.starts(with: prefixUnits)
      && text.dropFirst(prefixUnits.count).allSatisfy(digits)
  }

  private static func isOctalDigit(_ unit: UInt16) -> Bool {
    (0x30 ... 0x37).contains(unit)
  }

  private static func isHexadecimalDigit(_ unit: UInt16) -> Bool {
    CodeUnits.isASCIIDigit(unit) || (0x41 ... 0x46).contains(unit) || (0x61 ... 0x66).contains(unit)
  }

  private struct Scanner {
    let units: [UInt16]
    var position = 0

    init(_ units: [UInt16]) {
      self.units = units
    }

    var isAtEnd: Bool {
      position == units.count
    }

    mutating func skip(_ unit: UInt16) -> Bool {
      guard position < units.count, units[position] == unit else {
        return false
      }
      position += 1
      return true
    }

    mutating func skipSign() {
      _ = skip(0x2B) || skip(CodeUnits.hyphenMinus)
    }

    mutating func skipDigits() -> Int {
      let start = position
      while position < units.count, CodeUnits.isASCIIDigit(units[position]) {
        position += 1
      }
      return position - start
    }
  }
}

/// `JSON.stringify(string)` as UTF-16 code units: the seven short escapes and
/// `\u00xx` for the other C0 controls.
enum JSONStringText {
  static func encode(_ text: [UInt16]) -> [UInt16] {
    var output: [UInt16] = [CodeUnits.quotationMark]
    for unit in text {
      switch unit {
      case CodeUnits.quotationMark: output += Array("\\\"".utf16)
      case CodeUnits.reverseSolidus: output += Array("\\\\".utf16)
      case CodeUnits.lineFeed: output += Array("\\n".utf16)
      case CodeUnits.carriageReturn: output += Array("\\r".utf16)
      case CodeUnits.tab: output += Array("\\t".utf16)
      case 0x08: output += Array("\\b".utf16)
      case 0x0C: output += Array("\\f".utf16)
      case 0x00 ..< 0x20: output += Array("\\u00".utf16) + hexadecimal(unit)
      default: output.append(unit)
      }
    }
    output.append(CodeUnits.quotationMark)
    return output
  }

  private static func hexadecimal(_ unit: UInt16) -> [UInt16] {
    let digits = Array("0123456789abcdef".utf16)
    return [digits[Int(unit >> 4)], digits[Int(unit & 0xF)]]
  }
}

extension CodeUnits {
  static let apostrophe: UInt16 = 0x27
  static let percentSign: UInt16 = 0x25
  static let plusSign: UInt16 = 0x2B
  static let questionMark: UInt16 = 0x3F
  static let verticalLine: UInt16 = 0x7C
}
