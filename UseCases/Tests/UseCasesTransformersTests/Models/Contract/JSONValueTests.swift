import Testing
@testable import UseCasesTransformers

struct JSONValueTests {
  @Test
  func `every kind of value is read`() throws {
    let value = try #require(
      JSONValue
        .parse(#"{"a": null, "b": true, "c": 3, "d": 1.5, "e": "x", "f": [1], "g": {"h": 2}}"#),
    )

    #expect(value["a"] == .null)
    #expect(value["b"]?.boolValue == true)
    #expect(value["c"]?.integerValue == 3)
    #expect(value["d"] == .number(1.5))
    #expect(value["e"]?.stringValue == "x")
    #expect(value["f"]?.arrayValue == [.integer(1)])
    #expect(value["g"]?["h"]?.integerValue == 2)
  }

  @Test(arguments: ["", "not json", "{", "{\"a\":", "[1,"])
  func `text that is not JSON is nil`(text: String) {
    #expect(JSONValue.parse(text) == nil)
  }

  @Test
  func `a value of another type reads as missing, never as a crash`() throws {
    let value = try #require(JSONValue.parse(#"{"n": "3", "s": 3}"#))

    #expect(value["n"]?.integerValue == nil)
    #expect(value["s"]?.stringValue == nil)
    #expect(value["s"]?.boolValue == nil)
    #expect(value["s"]?.arrayValue == nil)
    #expect(value["absent"] == nil)
    #expect(JSONValue.integer(1)["a"] == nil)
  }
}
