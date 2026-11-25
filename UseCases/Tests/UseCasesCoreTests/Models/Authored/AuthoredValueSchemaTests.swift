import Testing
@testable import UseCasesCore

struct AuthoredValueSchemaTests {
  @Test(arguments: [
    (#"1"#, #"1.0"#),
    (#"-0"#, #"0.0"#),
    (#"100"#, #"1e2"#),
    (#""a""#, #""a""#),
    (#"true"#, #"true"#),
    (#"null"#, #"null"#),
    (#"[1,"a"]"#, #"[1.0,"a"]"#),
    (#"{"a":1,"b":[2]}"#, #"{"b":[2],"a":1}"#),
    (#"{}"#, #"{}"#),
    (#"[]"#, #"[]"#),
  ])
  func `two values written the same way, or in another order, are equal`(
    left: String,
    right: String,
  ) throws {
    #expect(try authored(left).isSchemaEqual(to: authored(right)))
    #expect(try authored(right).isSchemaEqual(to: authored(left)))
  }

  @Test(arguments: [
    (#"1"#, #"true"#),
    (#"0"#, #"false"#),
    (#"1"#, #""1""#),
    (#"1"#, #"1.5"#),
    (#"null"#, #"false"#),
    (#"null"#, #"0"#),
    (#""""#, #"null"#),
    (#"[1,2]"#, #"[2,1]"#),
    (#"[1]"#, #"[1,1]"#),
    (#"{"a":1}"#, #"{"a":2}"#),
    (#"{"a":1}"#, #"{"b":1}"#),
    (#"{"a":1}"#, #"{"a":1,"b":1}"#),
    (#"[]"#, #"{}"#),
    (#""a""#, #""A""#),
  ])
  func `two different values are not equal`(
    left: String,
    right: String,
  ) throws {
    #expect(try !authored(left).isSchemaEqual(to: authored(right)))
    #expect(try !authored(right).isSchemaEqual(to: authored(left)))
  }

  @Test
  func `text is equal scalar by scalar, not by canonical equivalence`() {
    let composed = AuthoredValue.string("\u{E9}")
    let decomposed = AuthoredValue.string("e\u{301}")

    #expect(!composed.isSchemaEqual(to: decomposed))
  }

  @Test
  func `a large integer is not equal to the nearest number`() {
    let number = AuthoredValue.number(9_007_199_254_740_992)

    #expect(!AuthoredValue.integer(9_007_199_254_740_993).isSchemaEqual(to: number))
    #expect(AuthoredValue.integer(9_007_199_254_740_992).isSchemaEqual(to: number))
  }

  @Test(arguments: [
    (#"42"#, "42"),
    (#"1.5"#, "1.5"),
    (#"true"#, "true"),
    (#"null"#, "null"),
    (#""text""#, "'text'"),
    (#""it's""#, #"'it\'s'"#),
    (#""a\\b""#, #"'a\\b'"#),
    (#""toggle\n""#, #"'toggle\n'"#),
    (#""a\r\tb""#, #"'a\r\tb'"#),
    (#""\u0000\u007f""#, #"'\u0000\u007f'"#),
    (#"[1,"a",null]"#, "[1, 'a', null]"),
    (#"{"a":[true],"b":{}}"#, "{'a': [true], 'b': {}}"),
    (#"[]"#, "[]"),
  ])
  func `a value is shown with text in single quotes`(
    json: String,
    expected: String,
  ) throws {
    #expect(try authored(json).schemaDescription == expected)
  }

  @Test
  func `a long value is cut short`() {
    let description = AuthoredValue.string(String(repeating: "x", count: 200)).schemaDescription

    #expect(description.unicodeScalars.count == 80)
    #expect(description.hasSuffix("..."))
    #expect(AuthoredValue.string(String(repeating: "x", count: 78)).schemaDescription.count == 80)
  }

  @Test(arguments: [
    (AuthoredValue.integer(3), 3.0 as Double?),
    (.number(2.5), 2.5),
    (.string("3"), nil),
    (.boolean(true), nil),
    (.null, nil),
  ])
  func `only an integer or a number has a numeric value`(
    value: AuthoredValue,
    expected: Double?,
  ) {
    #expect(value.numericValue == expected)
  }

  @Test(arguments: [(1.0, "1"), (0.0, "0"), (-3.0, "-3"), (0.5, "0.5"), (1e300, "1e+300")])
  func `a whole number is shown without its fraction`(
    number: Double,
    expected: String,
  ) {
    #expect(number.schemaNumberText == expected)
  }
}
