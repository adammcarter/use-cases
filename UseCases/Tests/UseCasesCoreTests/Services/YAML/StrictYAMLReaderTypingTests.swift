import Testing
@testable import UseCasesCore

struct StrictYAMLReaderTypingTests {
  private let reader = StrictYAMLReader()

  /// Plain scalars YAML 1.1 and YAML 1.2 read differently: on, off, yes and no in any case,
  /// base-60 numbers, dates and times, exponents without a point, octal and binary spellings,
  /// underscores, and the merge and value keys.
  private static let ambiguous = [
    "on", "On", "ON", "oN", "off", "Off", "OFF", "yes", "Yes", "YES", "yEs", "no", "No", "NO",
    "1:30", "190:20:30", "-1:30", "1:30.5", "10:00",
    "2024-01-01", "2026-02-30", "2024-01-01T10:00:00Z", "2024-01-01 10:00:00",
    "2001-12-14t21:59:43.10-05:00",
    "1e3", "1E3", "1.5e3", "1e+3", "1e-3", ".5e3",
    "0o17", "0b101", "-0b1", "1_000", "0x_1F", "-0x1F", "+0x1F",
    "017", "-017", "010", "08", "09", "0_7", "1_0.5",
    "<<", "=",
  ]

  /// Plain scalars both versions read as text, or as the same value.
  private static let alike = [
    "y", "n", "Y", "N", "2024-1-1", "0B101", "1.2.3", "1:30pm", "1,000", "v1.0", "yeah",
    "onward", "nope", "TrUe", "Yes please", "12:60", "0:30", ".", "+", "1e", "e3", "0o8", "0x",
    "Check it.", "a/b", "x-ray", "2024-01",
  ]

  @Test(arguments: ambiguous)
  func `a plain value that two YAML versions read differently must be quoted`(text: String) throws {
    let error = try #require(reader.attempt("title: \(text)\n").failure)

    guard case let .unquoted(location, found, .readDifferently) = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(location.line == 1)
    #expect(found == text)
    #expect(error.message.hasSuffix("quote it"))
    #expect(error.message.contains("'\(text)'"))
  }

  @Test(arguments: ambiguous)
  func `a plain key that two YAML versions read differently must be quoted`(text: String) throws {
    let error = try #require(reader.attempt("ok: 1\n\(text): value\n").failure)

    guard case let .unquoted(location, found, .readDifferently) = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(location.line == 2)
    #expect(found == text)
    #expect(error.message.hasSuffix("quote it"))
  }

  @Test(arguments: ambiguous)
  func `a plain list item that two YAML versions read differently must be quoted`(
    text: String,
  ) throws {
    let error = try #require(reader.attempt("steps:\n  - \(text)\n").failure)

    guard case .unquoted(_, _, .readDifferently) = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(error.line == 2)
  }

  @Test(arguments: ["[on]", "{k: off}", "[a, 1e3]", "{k: 2024-01-01}", "{on: v}", "[<<]"])
  func `the same holds inside a flow list or mapping`(text: String) throws {
    let error = try #require(reader.attempt("title: \(text)\n").failure)

    guard case .unquoted(_, _, .readDifferently) = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }
  }

  @Test(arguments: ambiguous)
  func `the same text quoted is read exactly as written`(text: String) {
    let double = reader.attempt("title: \"\(text)\"\n")
    let single = reader.attempt("title: '\(text)'\n")
    let key = reader.attempt("\"\(text)\": value\n")

    #expect(double.success == .members(["title": .string(text)]))
    #expect(single.success == .members(["title": .string(text)]))
    #expect(key.success == .members([text: .string("value")]))
  }

  @Test(arguments: ambiguous)
  func `a block scalar is always text`(text: String) {
    let literal = reader.attempt("title: |\n  \(text)\n")
    let folded = reader.attempt("title: >\n  \(text)\n")

    #expect(literal.success == .members(["title": .string("\(text)\n")]))
    #expect(folded.success == .members(["title": .string("\(text)\n")]))
  }

  @Test(arguments: ambiguous)
  func `a settings file is held to the same typing`(text: String) {
    #expect(reader.attempt("title: \(text)\n", kind: .settings).failure != nil)
  }

  @Test(arguments: alike)
  func `a plain scalar both versions read alike is read as written`(text: String) {
    let result = reader.attempt("title: \(text)\n")

    #expect(result.success == .members(["title": .string(text)]))
  }

  @Test(arguments: [
    ("42", AuthoredValue.integer(42)), ("-7", .integer(-7)), ("+7", .integer(7)),
    ("0", .integer(0)), ("-0", .integer(0)), ("007", .integer(7)), ("00", .integer(0)),
    ("0x1F", .integer(31)), ("0xff", .integer(255)),
    ("1.5", .number(1.5)), ("-1.5", .number(-1.5)), (".5", .number(0.5)), ("5.", .number(5)),
    ("1.5e+3", .number(1500)), ("1.5E-3", .number(0.0015)), ("0.0", .number(0)),

    ("true", .boolean(true)), ("True", .boolean(true)), ("TRUE", .boolean(true)),
    ("false", .boolean(false)), ("False", .boolean(false)), ("FALSE", .boolean(false)),
    ("null", .null), ("Null", .null), ("NULL", .null), ("~", .null), ("", .null),
    ("hello", .string("hello")),
  ])
  func `values are typed by the core schema`(
    text: String,
    expected: AuthoredValue,
  ) {
    let result = reader.attempt("n: \(text)\n")

    #expect(result.success == .members(["n": expected]))
  }

  @Test(arguments: ["", "42", "1.5", "true", "null", "~", "hello", "0x1F"])
  func `quoted scalars are always strings`(text: String) {
    #expect(reader.attempt("n: \"\(text)\"\n").success == .members(["n": .string(text)]))
    #expect(reader.attempt("n: '\(text)'\n").success == .members(["n": .string(text)]))
  }

  @Test
  func `an integer and a number stay apart`() {
    let result = reader.attempt("a: 1\nb: 1.0\nc: 1e0x\n")

    #expect(result.success == .members(["a": .integer(1), "b": .number(1), "c": .string("1e0x")]))
  }

  @Test(arguments: [
    ("9223372036854775807", Int.max),
    ("-9223372036854775808", Int.min),
    ("0x7FFFFFFFFFFFFFFF", Int.max),
    ("0000000000000000000000007", 7),
  ])
  func `an integer that fits in an Int is read exactly`(
    text: String,
    expected: Int,
  ) {
    #expect(reader.attempt("n: \(text)\n").success == .members(["n": .integer(expected)]))
  }

  @Test(arguments: [
    "9223372036854775808", "-9223372036854775809", "0x8000000000000000",
    "0o1000000000000000000000", "99999999999999999999",
  ])
  func `an integer too big for an Int is refused, never rounded`(text: String) throws {
    let value = try #require(reader.attempt("n: \(text)\n").failure)
    let key = try #require(reader.attempt("\(text): v\n").failure)

    #expect(value == .unquoted(
      YAMLLocation(file: "use-cases/a.yml", line: 1),
      text: text,
      problem: .integerTooLarge,
    ))
    #expect(key == value)
    #expect(value.message.contains("too big"))
  }

  @Test(arguments: [
    ".inf", ".Inf", ".INF", "+.inf", "-.inf", "-.Inf", "-.INF", ".nan", ".NaN", ".NAN",
    "1.0e+400", "1e400", "-1e400",
  ])
  func `a plain value that is not a JSON number must be quoted`(text: String) throws {
    let error = try #require(reader.attempt("n: \(text)\n").failure)

    #expect(error == .unquoted(
      YAMLLocation(file: "use-cases/a.yml", line: 1),
      text: text,
      problem: .notJSONNumber,
    ))
    #expect(error.message.hasSuffix("quote it"))
  }

  @Test(arguments: [".inf", ".nan", "1.0e+400", "-.Inf"])
  func `a number JSON cannot hold is fine once quoted`(text: String) {
    #expect(reader.attempt("n: \"\(text)\"\n").success == .members(["n": .string(text)]))
  }

  @Test(arguments: [
    "1", "01", "+1", "-1", "0", "00", "0x1F", "0o17", "1.5", ".5", "1e3", "~", "null", "Null",
    "NULL", "true", "True", "TRUE", "false", "False", "FALSE", ".inf", ".nan",
  ])
  func `a plain key that is not text must be quoted`(text: String) throws {
    let error = try #require(reader.attempt("ok: 1\n\(text): value\n").failure)

    guard case let .unquoted(location, found, _) = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(location.line == 2)
    #expect(found == text)
    #expect(error.message.hasSuffix("quote it"))
  }

  @Test(arguments: [
    "1", "01", "+1", "0x1F", "1.5", "~", "null", "true", "false", "", "0o17", "1e3", "on",
  ])
  func `a quoted key is text however it reads plain`(text: String) {
    let double = reader.attempt("\"\(text)\": value\n")
    let single = reader.attempt("'\(text)': value\n")

    #expect(double.success == .members([text: .string("value")]))
    #expect(single.success == .members([text: .string("value")]))
  }

  @Test
  func `two keys that differ only as numbers cannot both be plain`() {
    #expect(reader.attempt("01: a\n1: b\n").failure != nil)
    #expect(reader.attempt("\"01\": a\n\"1\": b\n").success != nil)
  }

  @Test(arguments: ["1", "true", "null", "0x1F"])
  func `a plain list item or value that is not text is still typed`(text: String) {
    #expect(reader.attempt("- \(text)\n").success != nil)
  }

  @Test
  func `an integer too big is fine once quoted`() {
    let result = reader.attempt("n: \"99999999999999999999\"\n")

    #expect(result.success == .members(["n": .string("99999999999999999999")]))
  }

  @Test
  func `a multi-line plain scalar is typed as the whole folded text`() {
    let result = reader.attempt("n: on\n  and off\n")

    #expect(result.success == .members(["n": .string("on and off")]))
  }
}
