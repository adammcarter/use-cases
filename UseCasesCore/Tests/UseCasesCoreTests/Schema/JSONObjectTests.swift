import Testing
@testable import UseCasesCore

/// A JSON object keeps its keys in document order, because two frozen
/// behaviours depend on it: `additionalProperties` diagnostics arrive in the
/// order the offending keys appear in the DATA, and the canonical JSON the
/// semantic hash is taken over sorts from that same key list.
struct JSONObjectTests {
  @Test
  func `an empty object has no keys`() {
    let object = JSONObject()

    #expect(object.isEmpty)
    #expect(object.keys.isEmpty)
    #expect(object.pairs.isEmpty)
  }

  @Test
  func `keys keep the order they were inserted in`() {
    var object = JSONObject()
    object["zebra"] = .number(1)
    object["alpha"] = .number(2)
    object["middle"] = .null

    #expect(object.keys == ["zebra", "alpha", "middle"])
  }

  @Test
  func `reassigning a key keeps its original position`() {
    var object = JSONObject([("a", .number(1)), ("b", .number(2))])
    object["a"] = .string("replaced")

    #expect(object.keys == ["a", "b"])
    #expect(object["a"] == .string("replaced"))
  }

  @Test
  func `a missing key reads as nil`() {
    let object = JSONObject([("a", .number(1))])

    #expect(object["missing"] == nil)
    #expect(object.contains("missing") == false)
    #expect(object.contains("a"))
  }

  @Test
  func `an explicit null is present and distinct from a missing key`() {
    let object = JSONObject([("a", .null)])

    #expect(object.contains("a"))
    #expect(object["a"] == JSONValue.null)
  }

  @Test
  func `equality ignores key order, matching JavaScript deep equality`() {
    let left = JSONObject([("a", .number(1)), ("b", .number(2))])
    let right = JSONObject([("b", .number(2)), ("a", .number(1))])

    #expect(left == right)
  }

  @Test
  func `equality still separates different values`() {
    let left = JSONObject([("a", .number(1))])
    let right = JSONObject([("a", .number(2))])

    #expect(left != right)
  }

  @Test
  func `an object built from duplicate keys keeps the first position and the last value`() {
    let object = JSONObject([("a", .number(1)), ("b", .number(2)), ("a", .number(3))])

    #expect(object.keys == ["a", "b"])
    #expect(object["a"] == .number(3))
  }

  @Test
  func `pairs walk the keys in order`() {
    let object = JSONObject([("z", .number(1)), ("a", .number(2))])

    #expect(object.pairs.map(\.key) == ["z", "a"])
    #expect(object.pairs.map(\.value) == [.number(1), .number(2)])
  }
}
