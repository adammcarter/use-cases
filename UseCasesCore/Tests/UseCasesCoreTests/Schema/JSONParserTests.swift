import Testing
@testable import UseCasesCore

/// The parser exists because Foundation's JSON reader hands back unordered
/// dictionaries, and two frozen behaviours need the document's own key order:
/// `additionalProperties` diagnostics follow the data's keys, and JSON-pointer
/// diagnostics have to name the member that really was there.
struct JSONParserTests {
  @Test(arguments: [
    ("null", JSONValue.null),
    ("true", JSONValue.bool(true)),
    ("false", JSONValue.bool(false)),
    ("0", JSONValue.number(0)),
    ("-0", JSONValue.number(0)),
    ("1", JSONValue.number(1)),
    ("-2.5", JSONValue.number(-2.5)),
    ("1e3", JSONValue.number(1000)),
    ("1E+3", JSONValue.number(1000)),
    ("1.5e-3", JSONValue.number(0.0015)),
    (#""""#, JSONValue.string("")),
    (#""abc""#, JSONValue.string("abc")),
    ("[]", JSONValue.array([])),
    ("{}", JSONValue.object(JSONObject())),
  ])
  func `parses a scalar document`(
    text: String,
    expected: JSONValue,
  ) throws {
    #expect(try JSONParser.parse(text) == expected)
  }

  @Test
  func `parses a nested document`() throws {
    let value = try JSONParser.parse(#"{"a":[1,{"b":null}],"c":{"d":"e"}}"#)

    #expect(value["a"]?.arrayValue?.count == 2)
    #expect(value["a"]?.arrayValue?[1]["b"] == JSONValue.null)
    #expect(value["c"]?["d"] == .string("e"))
  }

  @Test
  func `keeps object keys in document order`() throws {
    let value = try JSONParser.parse(#"{"zebra":1,"alpha":2,"_underscore":3}"#)

    #expect(value.objectValue?.keys == ["zebra", "alpha", "_underscore"])
  }

  @Test
  func `a duplicate key keeps the first position and the last value`() throws {
    let value = try JSONParser.parse(#"{"a":1,"b":2,"a":3}"#)

    #expect(value.objectValue?.keys == ["a", "b"])
    #expect(value["a"] == .number(3))
  }

  @Test
  func `ignores insignificant whitespace`() throws {
    let value = try JSONParser.parse(" {\n  \"a\" : [ 1 , 2 ]\t}\r\n ")

    #expect(value["a"] == .array([.number(1), .number(2)]))
  }

  @Test(arguments: [
    (#""a\"b""#, "a\"b"),
    (#""a\\b""#, "a\\b"),
    (#""a\/b""#, "a/b"),
    (#""\b\f\n\r\t""#, "\u{8}\u{C}\n\r\t"),
    (#""\u0041""#, "A"),
    (#""\u00e9""#, "é"),
    (#""\ud83d\ude00""#, "😀"),
  ])
  func `decodes a string escape`(
    text: String,
    expected: String,
  ) throws {
    #expect(try JSONParser.parse(text) == .string(expected))
  }

  @Test
  func `keeps a literal non-ascii character`() throws {
    #expect(try JSONParser.parse("\"é😀\"") == .string("é😀"))
  }

  @Test(arguments: [
    "",
    "   ",
    "{",
    "[",
    "{\"a\"}",
    "{\"a\":}",
    "{\"a\":1,}",
    "[1,]",
    "[1 2]",
    "{'a':1}",
    "nul",
    "truex",
    "01",
    "+1",
    ".5",
    "1.",
    "1e",
    "\"unterminated",
    "\"bad \\q escape\"",
    "\"\\u12\"",
    "{\"a\":1} trailing",
    "undefined",
    "NaN",
    "Infinity",
  ])
  func `refuses a malformed document`(text: String) {
    #expect(throws: SchemaError.self) {
      try JSONParser.parse(text)
    }
  }

  @Test
  func `a parse failure carries the frozen parse error code`() {
    #expect {
      try JSONParser.parse("{")
    } throws: { error in
      guard let schemaError = error as? SchemaError else { return false }
      return schemaError.code == "parse_error" && schemaError.message.isEmpty == false
    }
  }

  @Test
  func `parses a very long array`() throws {
    let text = "[" + (0 ..< 5000).map(String.init).joined(separator: ",") + "]"
    let value = try JSONParser.parse(text)

    #expect(value.arrayValue?.count == 5000)
    #expect(value.arrayValue?.last == .number(4999))
  }

  @Test
  func `parses deeply nested arrays`() throws {
    let depth = 200
    let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    var value = try JSONParser.parse(text)

    var measured = 0
    while let inner = value.arrayValue?.first {
      measured += 1
      value = inner
    }

    #expect(measured == depth - 1)
  }

  @Test
  func `a large integer keeps double precision, exactly as JavaScript does`() throws {
    let value = try JSONParser.parse("12345678901234567890")

    #expect(value.numberValue == 12_345_678_901_234_567_890 as Double)
  }
}
