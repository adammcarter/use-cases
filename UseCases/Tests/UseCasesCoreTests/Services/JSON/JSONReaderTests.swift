import Testing
@testable import UseCasesCore

struct JSONReaderTests {
  static let backslash = "\\"

  let reader = JSONReader()

  @Test(arguments: [
    ("null", AuthoredValue.null),
    ("true", .boolean(true)),
    ("false", .boolean(false)),
    ("0", .integer(0)),
    ("-0", .integer(0)),
    ("42", .integer(42)),
    ("-7", .integer(-7)),
    ("9223372036854775807", .integer(Int.max)),
    ("-9223372036854775808", .integer(Int.min)),
    ("1.0", .number(1)),
    ("1.5", .number(1.5)),
    ("-0.25", .number(-0.25)),
    ("1e2", .number(100)),
    ("1E+2", .number(100)),
    ("25e-1", .number(2.5)),
    ("\"\"", .string("")),
    ("\"text\"", .string("text")),
    ("[]", .array([])),
    ("{}", .object([])),
    ("  \t\r\n[ 1 , 2 ]\n", .array([.integer(1), .integer(2)])),
  ])
  func `reads a value as the kind it was written as`(
    text: String,
    expected: AuthoredValue,
  ) throws {
    #expect(try reader.read(text) == expected)
  }

  @Test
  func `an integer stays an integer and a number stays a number`() throws {
    let value = try reader.read("[1, 1.0]")

    #expect(value == .array([.integer(1), .number(1)]))
    #expect(value != .array([.number(1), .integer(1)]))
  }

  @Test
  func `an object keeps its members in the order they were written`() throws {
    let value = try reader.read(#"{"b": 1, "a": 2, "c": [true]}"#)

    #expect(value == .object([
      AuthoredMember(
        key: "b",
        value: .integer(1),
      ),
      AuthoredMember(
        key: "a",
        value: .integer(2),
      ),
      AuthoredMember(
        key: "c",
        value: .array([.boolean(true)]),
      ),
    ]))
  }

  @Test(arguments: [
    (#"a\"b"#, "a\"b"),
    (#"a\\b"#, "a\\b"),
    (#"a\/b"#, "a/b"),
    (#"\b\f\n\r\t"#, "\u{8}\u{C}\n\r\t"),
    ("text with \u{E9} and \u{1F600}", "text with \u{E9} and \u{1F600}"),
  ])
  func `reads the plain escapes of a string`(
    body: String,
    expected: String,
  ) throws {
    #expect(try reader.read("\"" + body + "\"") == .string(expected))
  }

  /// Rows hold the four hex digits only, and the test writes the backslash, so a row cannot be
  /// turned into the character it stands for.
  @Test(arguments: [
    ("0041", "A"),
    ("00e9", "\u{E9}"),
    ("00E9", "\u{E9}"),
    ("00Ff", "\u{FF}"),
    ("0000", "\u{0}"),
    ("001f", "\u{1F}"),
    ("007f", "\u{7F}"),
    ("2028", "\u{2028}"),
    ("d7FF", "\u{D7FF}"),
    ("e000", "\u{E000}"),
    ("ffff", "\u{FFFF}"),
  ])
  func `reads a unicode escape of either case`(
    hex: String,
    expected: String,
  ) throws {
    let text = "\"" + Self.backslash + "u" + hex + "\""

    let value = try reader.read(text)

    #expect(value == .string(expected))
    #expect(text.unicodeScalars.count == 8)
  }

  @Test(arguments: [
    ("d83d", "de00", "\u{1F600}"),
    ("D83D", "DE00", "\u{1F600}"),
    ("d800", "dc00", "\u{10000}"),
    ("dbff", "dfff", "\u{10FFFF}"),
  ])
  func `reads a surrogate pair as one character`(
    high: String,
    low: String,
    expected: String,
  ) throws {
    let slash = Self.backslash
    let text = "\"" + slash + "u" + high + slash + "u" + low + "\""

    #expect(try reader.read(text) == .string(expected))
  }

  @Test(arguments: [
    "u12",
    "u12zz",
    "u00g1",
    "u",
    "x41",
    "a",
    "0",
    "U0041",
    "ud83d",
    "ud83dx",
    "ud800" + "x",
    "ude00",
    "udfff",
  ])
  func `refuses an escape that is not one`(body: String) {
    let text = "\"" + Self.backslash + body + "\""

    #expect(throws: JSONReadingError.self) {
      try reader.read(text)
    }
  }

  @Test(arguments: [
    ("ud83d", "u0041"),
    ("ud83d", "ud83d"),
    ("ud83d", "n"),
    ("ud83d", "ue000"),
  ])
  func `refuses a high surrogate not followed by a low one`(
    first: String,
    second: String,
  ) {
    let slash = Self.backslash
    let text = "\"" + slash + first + slash + second + "\""

    #expect(throws: JSONReadingError.invalidEscape(offset: 1)) {
      try reader.read(text)
    }
  }

  @Test(arguments: [
    ("", JSONReadingError.unexpectedEnd),
    ("   ", .unexpectedEnd),
    ("[1,", .unexpectedEnd),
    ("[1", .unexpectedEnd),
    ("{\"a\"", .unexpectedEnd),
    ("{\"a\":", .unexpectedEnd),
    ("\"abc", .unexpectedEnd),
    ("tru", .unexpectedEnd),
    ("nul1", .unexpectedCharacter(offset: 3)),
    ("[1,]", .unexpectedCharacter(offset: 3)),
    ("{\"a\":1,}", .unexpectedCharacter(offset: 7)),
    ("{a:1}", .unexpectedCharacter(offset: 1)),
    ("{\"a\" 1}", .unexpectedCharacter(offset: 5)),
    ("[1 2]", .unexpectedCharacter(offset: 3)),
    ("'a'", .unexpectedCharacter(offset: 0)),
    ("[1] x", .trailingContent(offset: 4)),
    ("1 2", .trailingContent(offset: 2)),
    ("01", .trailingContent(offset: 1)),
    ("-", .invalidNumber(offset: 0)),
    ("1.", .invalidNumber(offset: 0)),
    (".5", .unexpectedCharacter(offset: 0)),
    ("1e", .invalidNumber(offset: 0)),
    ("1e+", .invalidNumber(offset: 0)),
    ("-a", .invalidNumber(offset: 0)),
    ("1e999", .invalidNumber(offset: 0)),
    ("9223372036854775808", .integerOutOfRange(offset: 0)),
    ("-9223372036854775809", .integerOutOfRange(offset: 0)),
    ("[1, 123456789012345678901234567890]", .integerOutOfRange(offset: 4)),
    (#"{"a":1,"a":2}"#, .duplicateKey("a", offset: 7)),
    (#"{"a":1,"b":{"c":1,"c":2}}"#, .duplicateKey("c", offset: 18)),
    (#"[{"a":1},{"b":1,"b":1}]"#, .duplicateKey("b", offset: 16)),
    ("\"a\nb\"", .controlCharacterInString(offset: 2)),
    ("\"\u{1F}\"", .controlCharacterInString(offset: 1)),
  ])
  func `refuses text that is not JSON`(
    text: String,
    expected: JSONReadingError,
  ) {
    #expect(throws: expected) {
      try reader.read(text)
    }
  }

  @Test
  func `a delete character is an ordinary character of a string`() throws {
    #expect(try reader.read("\"\u{7F}\"") == .string("\u{7F}"))
  }
}
