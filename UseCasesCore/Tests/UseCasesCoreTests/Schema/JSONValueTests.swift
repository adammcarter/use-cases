import Testing
@testable import UseCasesCore

/// `JSONValue` is the document model every schema rule is evaluated against, so
/// it has to answer the same questions JavaScript does: what type is this, is it
/// a record (an object, NOT an array), and does it equal that other value.
struct JSONValueTests {
  @Test
  func `accessors return the payload of the matching case`() {
    #expect(JSONValue.string("x").stringValue == "x")
    #expect(JSONValue.number(2.5).numberValue == 2.5)
    #expect(JSONValue.bool(true).boolValue == true)
    #expect(JSONValue.array([.null]).arrayValue == [.null])
    #expect(JSONValue.object(JSONObject([("a", .null)])).objectValue?.keys == ["a"])
  }

  @Test
  func `accessors return nil for a mismatched case`() {
    #expect(JSONValue.null.stringValue == nil)
    #expect(JSONValue.string("2").numberValue == nil)
    #expect(JSONValue.number(1).boolValue == nil)
    #expect(JSONValue.array([]).objectValue == nil)
    #expect(JSONValue.object(JSONObject()).arrayValue == nil)
  }

  @Test(arguments: [
    (JSONValue.object(JSONObject()), true),
    (JSONValue.array([]), false),
    (JSONValue.null, false),
    (JSONValue.string(""), false),
  ])
  func `only an object counts as a record`(
    value: JSONValue,
    expected: Bool,
  ) {
    #expect(value.isRecord == expected)
  }

  @Test(arguments: [
    (JSONValue.null, "null"),
    (JSONValue.bool(false), "boolean"),
    (JSONValue.number(1), "number"),
    (JSONValue.string("a"), "string"),
    (JSONValue.array([]), "array"),
    (JSONValue.object(JSONObject()), "object"),
  ])
  func `every case names its JSON type`(
    value: JSONValue,
    expected: String,
  ) {
    #expect(value.typeName == expected)
  }

  @Test
  func `subscripting an object reads its member`() {
    let value = JSONValue.object(JSONObject([("a", .number(1))]))

    #expect(value["a"] == .number(1))
    #expect(value["b"] == nil)
  }

  @Test
  func `subscripting a non-object reads nothing`() {
    #expect(JSONValue.array([.number(1)])["0"] == nil)
    #expect(JSONValue.null["a"] == nil)
  }
}
