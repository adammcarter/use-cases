import Testing
@testable import UseCasesCore

/// The writer, not Foundation's `JSONEncoder`, produces every byte the CLI
/// publishes: `JSONEncoder` reorders object keys, and both the frozen envelope
/// and the canonical JSON the semantic hash is taken over depend on key order.
struct JSONWriterTests {
  @Test
  func `an integral number is written without a fractional part`() {
    let value = JSONValue.object(JSONObject([("a", .number(1))]))

    #expect(JSONWriter.encode(value) == #"{"a":1}"#)
  }

  @Test
  func `a fractional number survives being written`() {
    #expect(JSONWriter.encode(.number(1.5)) == "1.5")
  }

  @Test
  func `a null is written as null rather than vanishing`() {
    let value = JSONValue.object(JSONObject([("a", .null)]))

    #expect(JSONWriter.encode(value) == #"{"a":null}"#)
  }

  @Test
  func `an object is written in document order`() {
    let object = JSONObject([("zebra", .number(1)), ("alpha", .number(2))])

    #expect(JSONWriter.encode(.object(object)) == #"{"zebra":1,"alpha":2}"#)
  }

  @Test
  func `a nested value is written with every case in place`() {
    let value = JSONValue.object(JSONObject([
      ("string", .string("x")),
      ("number", .number(-3.25)),
      ("bool", .bool(true)),
      ("nothing", .null),
      ("array", .array([.number(1), .string("two")])),
      ("object", .object(JSONObject([("nested", .bool(false))]))),
    ]))

    #expect(
      JSONWriter.encode(value) == #"{"string":"x","number":-3.25,"bool":true,"nothing":null,"#
        + #""array":[1,"two"],"object":{"nested":false}}"#,
    )
  }

  @Test
  func `a document survives a round trip through the parser`() throws {
    let value = JSONValue.object(JSONObject([
      ("a", .array([.number(1), .null])),
      ("b", .object(JSONObject([("c", .string("d"))]))),
    ]))

    #expect(try JSONParser.parse(JSONWriter.encode(value)) == value)
  }
}
