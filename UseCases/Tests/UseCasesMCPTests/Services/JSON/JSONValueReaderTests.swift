import MCP
import Testing
@testable import UseCasesMCP

struct JSONValueReaderTests {
  private let reader = JSONValueReader()

  @Test(arguments: [
    ("1", Value.int(1)),
    ("-7", .int(-7)),
    ("1.5", .double(1.5)),
    ("true", .bool(true)),
    ("false", .bool(false)),
    ("null", .null),
    (#""text""#, .string("text")),
    ("[]", .array([])),
    ("{}", .object([:])),
    (#"{"a": [1, {"b": null}]}"#, .object(["a": .array([.int(1), .object(["b": .null])])])),
    ("9007199254740993", .int(9_007_199_254_740_993)),
    (#""café 😀""#, .string("caf\u{E9} \u{1F600}")),
  ])
  func `JSON reads as the value it is`(
    text: String,
    expected: Value,
  ) {
    #expect(reader.value(of: text) == expected)
  }

  @Test
  func `a number written with a fraction of zero is the same number`() throws {
    let value = try #require(reader.value(of: "1.0"))

    #expect(value.doubleValue == 1 || value.intValue == 1)
  }

  @Test(arguments: [
    "data:,hello",
    "data:text/plain;base64,aGVsbG8=",
    "data:image/png;base64,AAAA",
  ])
  func `a string that looks like a data URL stays a string, as written`(text: String) {
    #expect(reader.value(of: "\"\(text)\"") == .string(text))
    let member = ["{\"k\": \"", text, "\"}"].joined()

    #expect(reader.value(of: member) == .object(["k": .string(text)]))
  }

  @Test(arguments: ["", "{", "[1,", "nope", "{\"a\":}", "1 2"])
  func `text that is not one JSON value is nothing`(text: String) {
    #expect(reader.value(of: text) == nil)
  }
}
