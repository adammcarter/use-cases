/// A JSON reader that keeps the document's own key order.
///
/// Foundation's reader hands back unordered dictionaries, and two frozen
/// behaviours need the order the document was written in: `additionalProperties`
/// diagnostics follow the data's keys, and a JSON pointer has to name the member
/// that really was there.
public enum JSONParser {
  /// Parse `text` as a JSON document (RFC 8259, exactly one value).
  public static func parse(_ text: String) throws(SchemaError) -> JSONValue {
    var scanner = Scanner(characters: Array(text.unicodeScalars))
    return try scanner.parseDocument()
  }

  /// A single-pass recursive-descent scanner over unicode scalars.
  private struct Scanner {
    let characters: [Unicode.Scalar]
    var index = 0

    init(characters: [Unicode.Scalar]) {
      self.characters = characters
    }

    mutating func parseDocument() throws(SchemaError) -> JSONValue {
      skipWhitespace()
      let value = try parseValue()
      skipWhitespace()
      guard index == characters.count else {
        throw fail("Unexpected trailing content in JSON at position \(index).")
      }
      return value
    }

    private mutating func parseValue() throws(SchemaError) -> JSONValue {
      guard let character = peek() else {
        throw fail("Unexpected end of JSON input.")
      }
      switch character {
      case "{": return try parseObject()
      case "[": return try parseArray()
      case "\"": return try .string(parseString())
      case "t": try expect(word: "true")
        return .bool(true)
      case "f": try expect(word: "false")
        return .bool(false)
      case "n": try expect(word: "null")
        return .null
      default: return try .number(parseNumber())
      }
    }

    private mutating func parseObject() throws(SchemaError) -> JSONValue {
      index += 1
      var object = JSONObject()
      skipWhitespace()
      if peek() == "}" {
        index += 1
        return .object(object)
      }
      while true {
        skipWhitespace()
        guard peek() == "\"" else {
          throw fail("Expected a member name in JSON at position \(index).")
        }
        let key = try parseString()
        skipWhitespace()
        guard peek() == ":" else {
          throw fail("Expected ':' in JSON at position \(index).")
        }
        index += 1
        skipWhitespace()
        object[key] = try parseValue()
        skipWhitespace()
        switch peek() {
        case ",":
          index += 1
        case "}":
          index += 1
          return .object(object)
        default:
          throw fail("Expected ',' or '}' in JSON at position \(index).")
        }
      }
    }

    private mutating func parseArray() throws(SchemaError) -> JSONValue {
      index += 1
      var values: [JSONValue] = []
      skipWhitespace()
      if peek() == "]" {
        index += 1
        return .array(values)
      }
      while true {
        skipWhitespace()
        try values.append(parseValue())
        skipWhitespace()
        switch peek() {
        case ",":
          index += 1
        case "]":
          index += 1
          return .array(values)
        default:
          throw fail("Expected ',' or ']' in JSON at position \(index).")
        }
      }
    }

    private mutating func parseString() throws(SchemaError) -> String {
      index += 1
      var scalars = String.UnicodeScalarView()
      while true {
        guard let character = peek() else {
          throw fail("Unterminated string in JSON at position \(index).")
        }
        index += 1
        switch character {
        case "\"":
          return String(scalars)
        case "\\":
          try scalars.append(contentsOf: parseEscape())
        default:
          guard character.value >= 0x20 else {
            throw fail("Unescaped control character in JSON at position \(index).")
          }
          scalars.append(character)
        }
      }
    }

    /// The escapes JSON spells with a single character after the backslash.
    private static let simpleEscapes: [Unicode.Scalar: Unicode.Scalar] = [
      "\"": "\"",
      "\\": "\\",
      "/": "/",
      "b": Unicode.Scalar(0x08),
      "f": Unicode.Scalar(0x0C),
      "n": "\n",
      "r": "\r",
      "t": "\t",
    ]

    private mutating func parseEscape() throws(SchemaError) -> [Unicode.Scalar] {
      guard let character = peek() else {
        throw fail("Unterminated escape in JSON at position \(index).")
      }
      index += 1
      if character == "u" {
        return try [parseUnicodeEscape()]
      }
      guard let replacement = Self.simpleEscapes[character] else {
        throw fail("Unsupported escape '\\\(character)' in JSON at position \(index).")
      }
      return [replacement]
    }

    private mutating func parseUnicodeEscape() throws(SchemaError) -> Unicode.Scalar {
      let first = try parseHexadecimalQuad()
      guard first >= 0xD800, first <= 0xDBFF else {
        guard let scalar = Unicode.Scalar(first) else {
          throw fail("Invalid unicode escape in JSON at position \(index).")
        }
        return scalar
      }
      guard peek() == "\\", peek(offset: 1) == "u" else {
        throw fail("Unpaired surrogate in JSON at position \(index).")
      }
      index += 2
      let second = try parseHexadecimalQuad()
      guard second >= 0xDC00, second <= 0xDFFF else {
        throw fail("Unpaired surrogate in JSON at position \(index).")
      }
      let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
      guard let scalar = Unicode.Scalar(combined) else {
        throw fail("Invalid surrogate pair in JSON at position \(index).")
      }
      return scalar
    }

    private mutating func parseHexadecimalQuad() throws(SchemaError) -> UInt32 {
      var value: UInt32 = 0
      for _ in 0 ..< 4 {
        guard let character = peek(), let digit = character.hexadecimalDigitValue else {
          throw fail("Invalid unicode escape in JSON at position \(index).")
        }
        index += 1
        value = value << 4 | digit
      }
      return value
    }

    private mutating func parseNumber() throws(SchemaError) -> Double {
      let start = index
      if peek() == "-" {
        index += 1
      }
      try parseIntegerPart(from: start)
      try parseFractionPart()
      try parseExponentPart()
      let text = String(String.UnicodeScalarView(characters[start ..< index]))
      guard let value = Double(text) else {
        throw fail("Unreadable number '\(text)' in JSON at position \(start).")
      }
      return value
    }

    /// A leading zero may not be followed by more digits, exactly as JSON says.
    private mutating func parseIntegerPart(from start: Int) throws(SchemaError) {
      guard let leading = peek(), leading.isASCIIDigit else {
        throw fail("Unexpected token in JSON at position \(start).")
      }
      if leading == "0" {
        index += 1
      } else {
        skipDigits()
      }
    }

    private mutating func parseFractionPart() throws(SchemaError) {
      guard peek() == "." else {
        return
      }
      index += 1
      guard peek()?.isASCIIDigit == true else {
        throw fail("Missing fraction digits in JSON at position \(index).")
      }
      skipDigits()
    }

    private mutating func parseExponentPart() throws(SchemaError) {
      guard peek() == "e" || peek() == "E" else {
        return
      }
      index += 1
      if peek() == "+" || peek() == "-" {
        index += 1
      }
      guard peek()?.isASCIIDigit == true else {
        throw fail("Missing exponent digits in JSON at position \(index).")
      }
      skipDigits()
    }

    private mutating func skipDigits() {
      while peek()?.isASCIIDigit == true {
        index += 1
      }
    }

    private mutating func expect(word: String) throws(SchemaError) {
      for expected in word.unicodeScalars {
        guard peek() == expected else {
          throw fail("Unexpected token in JSON at position \(index).")
        }
        index += 1
      }
    }

    private mutating func skipWhitespace() {
      while let character = peek(), character == " " || character == "\t"
        || character == "\n" || character == "\r"
      {
        index += 1
      }
    }

    private func peek(offset: Int = 0) -> Unicode.Scalar? {
      let position = index + offset
      return position < characters.count ? characters[position] : nil
    }

    private func fail(_ message: String) -> SchemaError {
      .invalidJSON(message: message)
    }
  }
}

private extension Unicode.Scalar {
  var isASCIIDigit: Bool {
    self >= "0" && self <= "9"
  }

  var hexadecimalDigitValue: UInt32? {
    switch self {
    case "0" ... "9": value - 48
    case "a" ... "f": value - 87
    case "A" ... "F": value - 55
    default: nil
    }
  }
}
