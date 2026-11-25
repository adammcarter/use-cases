import Testing
@testable import UseCasesCore

struct YAML11SchemaTests {
  private let schema = YAML11Schema()

  @Test(arguments: ["", "~", "null", "Null", "NULL"])
  func `the null spellings are null`(text: String) {
    #expect(schema.resolve(text) == .null)
  }

  @Test(arguments: [
    ("true", true), ("True", true), ("TRUE", true), ("on", true), ("On", true), ("ON", true),
    ("oN", true), ("yes", true), ("Yes", true), ("YES", true), ("yEs", true),
    ("false", false), ("False", false), ("FALSE", false), ("off", false), ("Off", false),
    ("OFF", false), ("oFF", false), ("no", false), ("No", false), ("NO", false), ("nO", false),
  ])
  func `the boolean spellings are booleans in any case`(
    text: String,
    expected: Bool,
  ) {
    #expect(schema.resolve(text) == .boolean(expected))
  }

  @Test(arguments: ["y", "Y", "n", "N", "TrUe", "tRUE", "yess", "onn", "nope", "o"])
  func `the single letters and near misses are text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }

  @Test(arguments: [
    ("0", 0), ("42", 42), ("-42", -42), ("+42", 42), ("1_000", 1000), ("1_0_0", 100), ("1__", 1),
    ("017", 15), ("-017", -15), ("007", 7), ("00", 0), ("0_7", 7),
    ("0b101", 5), ("-0b101", -5), ("0b1_0", 2), ("0x1F", 31), ("0x_1F", 31), ("-0x1F", -31),
    ("+0xff", 255), ("20240101", 20_240_101),
  ])
  func `integers are read in binary, octal, decimal and hexadecimal`(
    text: String,
    expected: Int,
  ) {
    #expect(schema.resolve(text) == .integer(.exact(expected)))
  }

  @Test(arguments: ["08", "0o17", "0B101", "_1", "0b2", "0xG", "1e3", "1 000", "00_9"])
  func `things that only look like integers are text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }

  @Test(arguments: ["1:30", "190:20:30", "-1:30", "+1:30", "1_0:30", "1:3", "12:59:59"])
  func `base-60 integers are base-60 numbers`(text: String) {
    #expect(schema.resolve(text) == .sexagesimal)
  }

  @Test(arguments: ["1:30.5", "190:20:30.15", "-1:30.", "1_0:30.5"])
  func `base-60 floats are base-60 numbers`(text: String) {
    #expect(schema.resolve(text) == .sexagesimal)
  }

  @Test(arguments: ["0:30", "1:60", "1:", ":30", "1:30:", "1:300", "a:30"])
  func `colon spellings that are not base 60 are text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }

  @Test(arguments: [
    ("1.5", 1.5), ("-1.5", -1.5), ("+1.5", 1.5), (".5", 0.5), ("-.5", -0.5), ("5.", 5),
    ("1_0.5", 10.5), ("1.5e+3", 1500), ("1.5E-3", 0.0015), (".5e+1", 5), ("1.e+2", 100),
  ])
  func `floats need a point, and a signed exponent if they have one`(
    text: String,
    expected: Double,
  ) {
    #expect(schema.resolve(text) == .number(expected))
  }

  @Test(arguments: [
    "1e3",
    "1E3",
    "1.5e3",
    "1e+3",
    "1e-3",
    ".5e3",
    ".",
    "-.",
    "1.2.3",
    ".e+3",
    "e3"
  ])
  func `an exponent without a sign, or no digits, is text`(text: String) {
    #expect(schema.resolve(text) == .text)
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

  @Test(arguments: [".nan", ".NaN", ".NAN"])
  func `not-a-number is a number`(text: String) {
    guard case let .number(value) = schema.resolve(text) else {
      Issue.record("\(text) was not read as a number")
      return
    }

    #expect(value.isNaN)
  }

  @Test(arguments: [
    "2024-01-01", "2026-02-30", "0001-01-01",
    "2001-12-14t21:59:43.10-05:00", "2001-12-14T21:59:43.10-05:00", "2001-12-14 21:59:43.10 -5",
    "2001-12-15 2:59:43.10", "2002-12-14 10:00:00", "2002-12-14\t10:00:00", "2001-12-14T21:59:43Z",
    "2001-12-14T21:59:43 Z", "2001-12-14T21:59:43.5+05", "2001-1-1 1:00:00",
  ])
  func `dates and times are timestamps`(text: String) {
    #expect(schema.resolve(text) == .timestamp)
  }

  @Test(arguments: [
    "2024-1-1", "24-01-01", "2024-01-011", "2024/01/01", "2024-01-01T", "2024-01-01 10:00",
    "2024-01-01T10", "2024-01", "2024-01-01x",
  ])
  func `other things that look like dates are text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }

  @Test
  func `the merge key and the value key are their own readings`() {
    #expect(schema.resolve("<<") == .mergeKey)
    #expect(schema.resolve("=") == .valueKey)
  }

  @Test(arguments: ["<", "<<<", "==", "< <", "hello", "x"])
  func `near misses of the merge key and the value key are text`(text: String) {
    #expect(schema.resolve(text) == .text)
  }
}
