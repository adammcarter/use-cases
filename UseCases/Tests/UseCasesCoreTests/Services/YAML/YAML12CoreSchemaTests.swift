import Testing
@testable import UseCasesCore

struct YAML12CoreSchemaTests {
  private let schema = YAML12CoreSchema()

  @Test(arguments: ["", "~", "null", "Null", "NULL"])
  func `the null spellings are null`(text: String) {
    #expect(schema.resolve(text) == .null)
  }

  @Test(arguments: [
    ("true", true), ("True", true), ("TRUE", true),
    ("false", false), ("False", false), ("FALSE", false),
  ])
  func `the boolean spellings are booleans`(
    text: String,
    expected: Bool,
  ) {
    #expect(schema.resolve(text) == .boolean(expected))
  }

  @Test(arguments: [
    ("0", 0), ("-0", 0), ("+0", 0), ("42", 42), ("-42", -42), ("+42", 42), ("007", 7),
    ("0o17", 15), ("0o0", 0), ("0x1F", 31), ("0xff", 255), ("0xFFFFFFFF", 4_294_967_295),
    ("9223372036854775807", Int.max), ("-9223372036854775808", Int.min),
  ])
  func `integers are read in decimal, octal and hexadecimal`(
    text: String,
    expected: Int,
  ) {
    #expect(schema.resolve(text) == .integer(.exact(expected)))
  }

  @Test(arguments: ["9223372036854775808", "-9223372036854775809", "0x8000000000000000"])
  func `an integer beyond Int is too large rather than rounded`(text: String) {
    #expect(schema.resolve(text) == .integer(.tooLarge))
  }

  @Test(arguments: [
    ("1.5", 1.5), ("-1.5", -1.5), ("+1.5", 1.5), (".5", 0.5), ("-.5", -0.5), ("5.", 5),
    ("1e3", 1000), ("1E3", 1000), ("1.5e3", 1500), ("1e-3", 0.001), ("1e+3", 1000),
    (".5e1", 5), ("0.0", 0), ("-0.0", -0.0),
  ])
  func `floats are read as numbers`(
    text: String,
    expected: Double,
  ) {
    #expect(schema.resolve(text) == .number(expected))
  }

  @Test(arguments: [
    (".inf", Double.infinity), (".Inf", .infinity), (".INF", .infinity), ("+.inf", .infinity),
    ("-.inf", -.infinity), ("-.INF", -.infinity),
  ])
  func `infinity is a number`(
    text: String,
    expected: Double,
  ) {
    #expect(schema.resolve(text) == .number(expected))
  }

  @Test(arguments: ["1e400", "-1e400", "1.0e+400", "9e9999"])
  func `a float too big for a Double reads as infinity`(text: String) {
    guard case let .number(value) = schema.resolve(text) else {
      Issue.record("\(text) was not read as a number")
      return
    }

    #expect(value.isInfinite)
  }

  @Test(arguments: [".nan", ".NaN", ".NAN"])
  func `not-a-number is a number`(text: String) {
    guard case let .number(value) = schema.resolve(text) else {
      Issue.record("\(text) was not read as a number")
      return
    }

    #expect(value.isNaN)
  }

  @Test(arguments: [
    "on", "off", "yes", "no", "y", "n", "1:30", "2024-01-01", "0b101", "1_000", "<<", "=",
    "hello", "1e", "0o8", "0x", "0xG", "1.2.3", ".", "+", "1,000", "TrUe", "nULL", "-0x1F",
    "0B101", "--1", "1 2", " 1", "1 ",
  ])
  func `everything else is text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }
}
