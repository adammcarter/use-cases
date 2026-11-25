import Testing
@testable import UseCasesCore

struct PlainScalarTyperTests {
  private let typer = PlainScalarTyper()

  @Test(arguments: [
    ("", AuthoredValue.null), ("~", .null), ("null", .null), ("Null", .null), ("NULL", .null),
    ("true", .boolean(true)), ("False", .boolean(false)), ("TRUE", .boolean(true)),
    ("0", .integer(0)), ("-7", .integer(-7)), ("+7", .integer(7)), ("007", .integer(7)),
    ("00", .integer(0)), ("20240101", .integer(20_240_101)), ("0x1F", .integer(31)), (
      "0x7FFFFFFFFFFFFFFF",
      .integer(Int.max),
    ),
    ("9223372036854775807", .integer(Int.max)), ("-9223372036854775808", .integer(Int.min)),
    ("1.5", .number(1.5)), (".5", .number(0.5)), ("5.", .number(5)), ("-1.5e-3", .number(-0.0015)),
    ("1.5e+3", .number(1500)),
    ("hello", .string("hello")), ("Check it.", .string("Check it.")), ("1.2.3", .string("1.2.3")),
    ("y", .string("y")), ("n", .string("n")), ("2024-1-1", .string("2024-1-1")),
    ("0B101", .string("0B101")), ("1,000", .string("1,000")), ("v1.0", .string("v1.0")),
    ("yeah", .string("yeah")), ("1:30pm", .string("1:30pm")), ("TrUe", .string("TrUe")),
  ])
  func `a plain scalar both versions read alike gets the core schema's value`(
    text: String,
    expected: AuthoredValue,
  ) {
    #expect(typer.type(of: text) == .value(expected))
  }

  @Test(arguments: [
    "on", "On", "ON", "oN", "off", "Off", "OFF", "yes", "Yes", "YES", "yEs", "no", "No", "NO",
    "1:30", "190:20:30", "-1:30", "1:30.5",
    "2024-01-01", "2026-02-30", "2024-01-01T10:00:00Z", "2024-01-01 10:00:00",
    "2001-12-14t21:59:43.10-05:00",
    "1e3", "1E3", "1.5e3", "1e+3", "1e-3", ".5e3",
    "0o17", "0o0", "0b101", "-0b1", "1_000", "1__", "0x_1F", "-0x1F", "+0x1F",
    "017", "-017", "010", "08", "09", "0_7", "1_0.5",
    "<<", "=",
  ])
  func `a plain scalar the two versions read differently is refused for quoting`(text: String) {
    guard case .readDifferently = typer.type(of: text) else {
      Issue.record("\(text) was not refused")
      return
    }
  }

  @Test(arguments: [
    ("on", YAMLResolvedScalar.boolean(true), YAMLResolvedScalar.text),
    ("No", .boolean(false), .text),
    ("1:30", .sexagesimal, .text),
    ("2024-01-01", .timestamp, .text),
    ("1e3", .text, .number(1000)),
    ("0o17", .text, .integer(.exact(15))),
    ("0b101", .integer(.exact(5)), .text),
    ("017", .integer(.exact(15)), .integer(.exact(17))),
    ("010", .integer(.exact(8)), .integer(.exact(10))),
    ("08", .text, .integer(.exact(8))),
    ("<<", .mergeKey, .text),
    ("=", .valueKey, .text),
  ])
  func `a refusal says how each version reads the scalar`(
    text: String,
    yaml11: YAMLResolvedScalar,
    yaml12: YAMLResolvedScalar,
  ) {
    #expect(typer.type(of: text) == .readDifferently(yaml11: yaml11, yaml12: yaml12))
  }

  @Test(arguments: [
    ".inf", ".Inf", ".INF", "+.inf", "-.inf", "-.Inf", "-.INF", ".nan", ".NaN", ".NAN",
    "1.0e+400", "1e400", "-1e400", "1.5E+999", "9e9999",
  ])
  func `a number JSON cannot hold is refused for quoting`(text: String) {
    #expect(typer.type(of: text) == .notJSONNumber)
  }

  @Test(arguments: [
    "9223372036854775808", "-9223372036854775809", "0x8000000000000000",
    "0o1000000000000000000000", "99999999999999999999999",
  ])
  func `an integer too big for Int is refused rather than rounded`(text: String) {
    #expect(typer.type(of: text) == .integerTooLarge)
  }
}
