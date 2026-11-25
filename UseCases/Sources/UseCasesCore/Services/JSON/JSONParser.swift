/// One pass over a JSON text, read as Unicode scalars.
struct JSONParser {
  private let scalars: [Unicode.Scalar]
  private var position = 0

  init(text: String) {
    scalars = Array(text.unicodeScalars)
  }

  mutating func parseDocument() throws(JSONReadingError) -> AuthoredValue {
    skipWhitespace()
    let value = try parseValue()
    skipWhitespace()

    guard position == scalars.count else {
      throw .trailingContent(offset: position)
    }

    return value
  }

  private var current: Unicode.Scalar? {
    position < scalars.count ? scalars[position] : nil
  }

  private mutating func skipWhitespace() {
    while let scalar = current, Self.whitespace.contains(scalar) {
      position += 1
    }
  }

  private mutating func parseValue() throws(JSONReadingError) -> AuthoredValue {
    guard let scalar = current else {
      throw .unexpectedEnd
    }

    switch scalar {
    case "{": return try parseObject()
    case "[": return try parseArray()
    case "\"": return try .string(parseString())
    case "t": return try parseLiteral("true", as: .boolean(true))
    case "f": return try parseLiteral("false", as: .boolean(false))
    case "n": return try parseLiteral("null", as: .null)
    case "-", "0" ... "9": return try parseNumber()
    default: throw .unexpectedCharacter(offset: position)
    }
  }

  private mutating func parseLiteral(
    _ word: String,
    as value: AuthoredValue,
  ) throws(JSONReadingError) -> AuthoredValue {
    for expected in word.unicodeScalars {
      guard let scalar = current else {
        throw .unexpectedEnd
      }
      guard scalar == expected else {
        throw .unexpectedCharacter(offset: position)
      }
      position += 1
    }

    return value
  }

  private mutating func expect(_ expected: Unicode.Scalar) throws(JSONReadingError) {
    guard let scalar = current else {
      throw .unexpectedEnd
    }
    guard scalar == expected else {
      throw .unexpectedCharacter(offset: position)
    }
    position += 1
  }

  private mutating func parseArray() throws(JSONReadingError) -> AuthoredValue {
    try expect("[")
    skipWhitespace()

    var elements: [AuthoredValue] = []
    if current == "]" {
      position += 1
      return .array(elements)
    }

    while true {
      skipWhitespace()
      try elements.append(parseValue())
      skipWhitespace()

      if try endsCollection(closing: "]") {
        return .array(elements)
      }
    }
  }

  private mutating func parseObject() throws(JSONReadingError) -> AuthoredValue {
    try expect("{")
    skipWhitespace()

    var members: [AuthoredMember] = []
    var seen: Set<ExactText> = []
    if current == "}" {
      position += 1
      return .object(members)
    }

    while true {
      skipWhitespace()
      let keyOffset = position
      let key = try parseString()
      guard seen.insert(ExactText(key)).inserted else {
        throw .duplicateKey(key, offset: keyOffset)
      }
      skipWhitespace()
      try expect(":")
      skipWhitespace()
      let value = try parseValue()
      members.append(AuthoredMember(
        key: key,
        value: value,
      ))
      skipWhitespace()

      if try endsCollection(closing: "}") {
        return .object(members)
      }
    }
  }

  /// Reads the `,` or the closing bracket after an element; true when the collection is over.
  private mutating func endsCollection(
    closing: Unicode.Scalar,
  ) throws(JSONReadingError) -> Bool {
    guard let scalar = current else {
      throw .unexpectedEnd
    }

    position += 1
    if scalar == closing {
      return true
    }
    guard scalar == "," else {
      throw .unexpectedCharacter(offset: position - 1)
    }

    return false
  }

  private mutating func parseString() throws(JSONReadingError) -> String {
    try expect("\"")

    var text = String.UnicodeScalarView()
    while true {
      guard let scalar = current else {
        throw .unexpectedEnd
      }

      switch scalar {
      case "\"":
        position += 1
        return String(text)
      case "\\":
        try text.append(parseEscape())
      case "\u{0}" ... "\u{1F}":
        throw .controlCharacterInString(offset: position)
      default:
        text.append(scalar)
        position += 1
      }
    }
  }

  /// Reads a backslash escape; position starts on the backslash.
  private mutating func parseEscape() throws(JSONReadingError) -> Unicode.Scalar {
    let start = position
    position += 1

    guard let scalar = current else {
      throw .unexpectedEnd
    }

    position += 1
    if scalar == "u" {
      return try parseUnicodeEscape(start: start)
    }
    guard let plain = Self.simpleEscapes[scalar] else {
      throw .invalidEscape(offset: start)
    }

    return plain
  }

  /// Reads the four hex digits after `\u`, joining a surrogate pair into one scalar.
  private mutating func parseUnicodeEscape(
    start: Int,
  ) throws(JSONReadingError) -> Unicode.Scalar {
    let unit = try parseHexUnit(start: start)

    switch unit {
    case 0xD800 ... 0xDBFF:
      guard current == "\\", position + 1 < scalars.count, scalars[position + 1] == "u" else {
        throw .invalidEscape(offset: start)
      }
      position += 2
      let low = try parseHexUnit(start: start)
      guard (0xDC00 ... 0xDFFF).contains(low) else {
        throw .invalidEscape(offset: start)
      }
      let combined = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
      guard let scalar = Unicode.Scalar(combined) else {
        throw .invalidEscape(offset: start)
      }

      return scalar
    default:
      guard let scalar = Unicode.Scalar(unit) else {
        throw .invalidEscape(offset: start)
      }

      return scalar
    }
  }

  private mutating func parseHexUnit(start: Int) throws(JSONReadingError) -> UInt32 {
    var unit: UInt32 = 0
    for _ in 0 ..< 4 {
      guard let scalar = current, let digit = Self.hexValue(of: scalar) else {
        throw .invalidEscape(offset: start)
      }
      unit = unit * 16 + digit
      position += 1
    }

    return unit
  }

  private mutating func parseNumber() throws(JSONReadingError) -> AuthoredValue {
    let start = position

    if current == "-" {
      position += 1
    }
    try parseIntegerDigits(start: start)
    var isInteger = true
    if current == "." {
      isInteger = false
      position += 1
      try parseDigits(start: start)
    }
    if current == "e" || current == "E" {
      isInteger = false
      position += 1
      if current == "+" || current == "-" {
        position += 1
      }
      try parseDigits(start: start)
    }

    var literal = String.UnicodeScalarView()
    literal.append(contentsOf: scalars[start ..< position])
    let text = String(literal)

    if isInteger {
      guard let integer = Int(text) else {
        throw .integerOutOfRange(offset: start)
      }

      return .integer(integer)
    }
    guard let number = Double(text), number.isFinite else {
      throw .invalidNumber(offset: start)
    }

    return .number(number)
  }

  /// A lone `0`, or a digit 1-9 followed by any digits: JSON allows no leading zero.
  private mutating func parseIntegerDigits(start: Int) throws(JSONReadingError) {
    if current == "0" {
      position += 1
      return
    }

    try parseDigits(start: start)
  }

  private mutating func parseDigits(start: Int) throws(JSONReadingError) {
    guard let first = current, ("0" ... "9").contains(first) else {
      throw .invalidNumber(offset: start)
    }

    while let scalar = current, ("0" ... "9").contains(scalar) {
      position += 1
    }
  }

  private static let whitespace: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r"]

  private static let simpleEscapes: [Unicode.Scalar: Unicode.Scalar] = [
    "\"": "\"",
    "\\": "\\",
    "/": "/",
    "b": "\u{8}",
    "f": "\u{C}",
    "n": "\n",
    "r": "\r",
    "t": "\t",
  ]

  private static func hexValue(of scalar: Unicode.Scalar) -> UInt32? {
    switch scalar {
    case "0" ... "9": scalar.value - 48
    case "a" ... "f": scalar.value - 97 + 10
    case "A" ... "F": scalar.value - 65 + 10
    default: nil
    }
  }
}
