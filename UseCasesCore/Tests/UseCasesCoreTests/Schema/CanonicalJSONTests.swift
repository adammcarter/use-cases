import Testing
@testable import UseCasesCore

/// The canonical form is what a semantic hash is taken over, so every rule in it
/// is frozen contract: keys sorted the way JavaScript's `localeCompare` sorts
/// them (lowercase before uppercase, punctuation before letters), no spaces, and
/// JSON.stringify's own string escaping.
struct CanonicalJSONTests {
  private func object(_ pairs: [(String, JSONValue)]) -> JSONValue {
    .object(JSONObject(pairs))
  }

  @Test(arguments: [
    (JSONValue.null, "null"),
    (JSONValue.bool(true), "true"),
    (JSONValue.bool(false), "false"),
    (JSONValue.number(1), "1"),
    (JSONValue.number(1.5), "1.5"),
    (JSONValue.string("abc"), #""abc""#),
    (JSONValue.array([]), "[]"),
    (JSONValue.object(JSONObject()), "{}"),
  ])
  func `encodes a scalar exactly as JSON stringify does`(
    value: JSONValue,
    expected: String,
  ) {
    #expect(CanonicalJSON.encode(value) == expected)
  }

  @Test
  func `sorts keys case-insensitively first, lowercase before uppercase`() {
    let sorted = object([("zebra", .number(1)), ("alpha", .number(2)), ("Beta", .number(3))])
    let cased = object([("b", .number(1)), ("B", .number(2)), ("a", .number(3)), ("A", .number(4))])

    #expect(CanonicalJSON.encode(sorted) == #"{"alpha":2,"Beta":3,"zebra":1}"#)
    #expect(CanonicalJSON.encode(cased) == #"{"a":3,"A":4,"b":1,"B":2}"#)
  }

  @Test
  func `sorts punctuation ahead of letters, underscore before dash before dot`() {
    let value = object([
      ("a_b", .number(1)),
      ("a-b", .number(2)),
      ("a.b", .number(3)),
      ("ab", .number(4)),
    ])

    #expect(CanonicalJSON.encode(value) == #"{"a_b":1,"a-b":2,"a.b":3,"ab":4}"#)
  }

  @Test
  func `sorts digits lexicographically rather than numerically`() {
    let value = object([("item10", .number(1)), ("item9", .number(2)), ("item1", .number(3))])

    #expect(CanonicalJSON.encode(value) == #"{"item1":3,"item10":1,"item9":2}"#)
  }

  @Test
  func `sorts an accented key between its base letter and the next`() {
    let value = object([("é", .number(1)), ("e", .number(2)), ("f", .number(3))])

    #expect(CanonicalJSON.encode(value) == "{\"e\":2,\"é\":1,\"f\":3}")
  }

  @Test
  func `sorts a tilde key ahead of a letter key`() {
    let value = object([("vendor.com/key", .number(1)), ("a~b", .number(2))])

    #expect(CanonicalJSON.encode(value) == #"{"a~b":2,"vendor.com/key":1}"#)
  }

  @Test
  func `encodes nested structures depth first`() {
    let value = object([
      ("use_cases", .array([object([("id", .string("a.b")), ("tags", .array([.string("x")]))])])),
      ("schema_version", .number(1)),
    ])

    #expect(
      CanonicalJSON.encode(value)
        == #"{"schema_version":1,"use_cases":[{"id":"a.b","tags":["x"]}]}"#,
    )
  }

  @Test
  func `keeps empty containers`() {
    let value = object([("a", .object(JSONObject())), ("b", .array([]))])

    #expect(CanonicalJSON.encode(value) == #"{"a":{},"b":[]}"#)
  }

  @Test
  func `escapes a string the way JSON stringify escapes it`() {
    let value = JSONValue.string("a\"b\\c\nd\te\u{1}")

    #expect(CanonicalJSON.encode(value) == #""a\"b\\c\nd\te\u0001""#)
  }

  @Test
  func `escapes the low control characters as four hex digits`() {
    #expect(CanonicalJSON.encode(.string("\u{0}\u{1F}")) == #""\u0000\u001f""#)
  }

  @Test
  func `leaves non-ascii characters unescaped`() {
    #expect(CanonicalJSON.encode(.string("é😀")) == "\"é😀\"")
  }

  @Test
  func `encodes a mixed array in place`() {
    let value = JSONValue.array([
      .number(1), .string("a"), .null, .bool(true), .array([]), .object(JSONObject()),
    ])

    #expect(CanonicalJSON.encode(value) == #"[1,"a",null,true,[],{}]"#)
  }

  @Test
  func `spells numbers the JavaScript way`() {
    let value = object([("x", .number(1)), ("y", .number(1e21)), ("z", .number(1e-7))])

    #expect(CanonicalJSON.encode(value) == #"{"x":1,"y":1e+21,"z":1e-7}"#)
  }
}
