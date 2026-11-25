import Testing
@testable import UseCasesCore

struct SchemaCheckerTests {
  /// A pattern that ends `$(?!\n)`, as JSON writes it.
  static let lineBreakGuard = #"^[a-z]+$(?!\\n)"#

  @Test(arguments: [
    (#"{"type":"string"}"#, #""x""#),
    (#"{"type":"integer"}"#, "1"),
    (#"{"type":"integer"}"#, "1.0"),
    (#"{"type":"integer"}"#, "1e2"),
    (#"{"type":"number"}"#, "1"),
    (#"{"type":"number"}"#, "1.5"),
    (#"{"type":"boolean"}"#, "false"),
    (#"{"type":"null"}"#, "null"),
    (#"{"type":"array"}"#, "[]"),
    (#"{"type":"object"}"#, "{}"),
    (#"{"required":["a"]}"#, "[]"),
    (#"{"required":["a"],"properties":{"a":{"type":"string"}}}"#, "42"),
    (#"{"properties":{"a":{"type":"string"}}}"#, #"{"b":1}"#),
    (#"{"additionalProperties":false}"#, "{}"),
    (#"{"additionalProperties":false}"#, "1"),
    (#"{"additionalProperties":true}"#, #"{"a":1}"#),
    (#"{"additionalProperties":{"type":"integer"}}"#, #"{"a":1,"b":2}"#),
    (#"{"properties":{"a":{}},"additionalProperties":false}"#, #"{"a":1}"#),
    (#"{"items":{"type":"integer"}}"#, "[1,2]"),
    (#"{"items":{"type":"integer"}}"#, "[]"),
    (#"{"items":{"type":"integer"}}"#, #""not an array""#),
    (#"{"minLength":1}"#, #""x""#),
    (#"{"minLength":1}"#, "0"),
    (#"{"maxLength":2}"#, #""ab""#),
    (#"{"minLength":2,"maxLength":2}"#, #""é""#),
    (#"{"maxLength":1}"#, #""😀""#),
    (#"{"minLength":0}"#, #""""#),
    (#"{"pattern":"b"}"#, #""abc""#),
    (#"{"pattern":"^a"}"#, "1"),
    (#"{"const":1}"#, "1"),
    (#"{"const":1}"#, "1.0"),
    (#"{"const":true}"#, "true"),
    (#"{"const":null}"#, "null"),
    (#"{"const":{"a":1,"b":2}}"#, #"{"b":2,"a":1}"#),
    (#"{"enum":["a","b"]}"#, #""b""#),
    (#"{"enum":[1,null]}"#, "null"),
    (#"{"minimum":1}"#, "1"),
    (#"{"minimum":1}"#, "1.5"),
    (#"{"minimum":1}"#, #""zero""#),
    (#"{"minimum":-1.5}"#, "-1.5"),
    (#"{"minItems":1}"#, "[0]"),
    (#"{"minItems":1}"#, #""""#),
    (#"{"uniqueItems":true}"#, "[1,2,3]"),
    (#"{"uniqueItems":true}"#, "[1,true,\"1\"]"),
    (#"{"uniqueItems":true}"#, #"[[1],[2],{"a":1},{"a":2}]"#),
    (#"{"uniqueItems":false}"#, "[1,1]"),
    (#"{"not":{"type":"string"}}"#, "1"),
    (#"{"oneOf":[{"type":"string"},{"type":"integer"}]}"#, "1"),
    (#"{"anyOf":[{"type":"string"},{"type":"integer"}]}"#, "1"),
    (#"{"anyOf":[{"type":"number"},{"type":"integer"}]}"#, "1"),
    (#"{"allOf":[{"type":"number"},{"minimum":1}]}"#, "1"),
    (#"{"if":{"type":"string"},"then":{"minLength":2}}"#, #""ab""#),
    (#"{"if":{"type":"string"},"then":{"minLength":2}}"#, "1"),
    (#"{"if":{"type":"string"},"else":{"minimum":2}}"#, "2"),
    (#"{"then":{"type":"string"}}"#, "1"),
    (#"{"propertyNames":{"pattern":"^[a-z]+$"}}"#, #"{"abc":1}"#),
    (#"{"propertyNames":{"pattern":"^[a-z]+$"}}"#, "1"),
    (#"{"format":"date"}"#, #""2024-02-29""#),
    (#"{"format":"date"}"#, "20260230"),
    (##"{"$ref":"#/$defs/n","$defs":{"n":{"type":"integer"}}}"##, "1"),
    (#"{"properties":{"a":true}}"#, #"{"a":"anything"}"#),
    (#"{"properties":{"a":false}}"#, #"{"b":"anything"}"#),
    (#"{}"#, #"{"anything":[1,null]}"#),
  ])
  func `a value that satisfies the schema has no failures`(
    schema: String,
    value: String,
  ) throws {
    let checker = try SchemaChecker(schema: authored(schema))

    #expect(try checker.check(authored(value)).isEmpty)
  }

  @Test(arguments: [
    (#"{"type":"string"}"#, "42", ["42 is not of type 'string'"]),
    (#"{"type":"string"}"#, "null", ["null is not of type 'string'"]),
    (#"{"type":"string"}"#, "[1, 2]", ["[1, 2] is not of type 'string'"]),
    (#"{"type":"integer"}"#, "1.5", ["1.5 is not of type 'integer'"]),
    (#"{"type":"integer"}"#, "true", ["true is not of type 'integer'"]),
    (#"{"type":"integer"}"#, #""1""#, ["'1' is not of type 'integer'"]),
    (#"{"type":"number"}"#, "true", ["true is not of type 'number'"]),
    (#"{"type":"boolean"}"#, "0", ["0 is not of type 'boolean'"]),
    (#"{"type":"null"}"#, "false", ["false is not of type 'null'"]),
    (#"{"type":"array"}"#, "{}", ["{} is not of type 'array'"]),
    (#"{"type":"object"}"#, "[]", ["[] is not of type 'object'"]),
    (#"{"required":["a","b"]}"#, #"{"a":1}"#, ["'b' is a required property"]),
    (
      #"{"required":["b","a"]}"#,
      "{}",
      ["'a' is a required property", "'b' is a required property"],
    ),
    (
      #"{"additionalProperties":false}"#,
      #"{"x":1}"#,
      ["Additional properties are not allowed ('x' was unexpected)"],
    ),
    (
      #"{"properties":{"a":{}},"additionalProperties":false}"#,
      #"{"a":1,"x":1,"y":2}"#,
      ["Additional properties are not allowed ('x', 'y' were unexpected)"],
    ),
    (
      #"{"additionalProperties":{"type":"integer"}}"#,
      #"{"a":1,"b":"s"}"#,
      ["'s' is not of type 'integer' at b"],
    ),
    (
      #"{"properties":{"a":{"properties":{"b":{"type":"string"}}}}}"#,
      #"{"a":{"b":7}}"#,
      ["7 is not of type 'string' at a/b"],
    ),
    (
      #"{"items":{"type":"string"}}"#,
      #"["a",1,true]"#,
      ["1 is not of type 'string' at 1", "true is not of type 'string' at 2"],
    ),
    (#"{"minLength":1}"#, #""""#, ["'' is too short (at least 1 characters)"]),
    (#"{"minLength":3}"#, #""é""#, ["'é' is too short (at least 3 characters)"]),
    (#"{"maxLength":2}"#, #""abc""#, ["'abc' is too long (at most 2 characters)"]),
    (
      #"{"maxLength":1}"#,
      #""\ud83d\udc68\u200d\ud83d\udc69""#,
      ["'\u{1F468}\u{200D}\u{1F469}' is too long (at most 1 characters)"],
    ),
    (#"{"pattern":"^[a-z]+$"}"#, #""Bad""#, ["'Bad' is not allowed"]),
    (#"{"const":1}"#, "2", ["2 is not allowed"]),
    (#"{"const":1}"#, "true", ["true is not allowed"]),
    (#"{"const":true}"#, "1", ["1 is not allowed"]),
    (#"{"const":"required"}"#, #""optional""#, ["'optional' is not allowed"]),
    (#"{"const":{"a":1}}"#, #"{"a":2}"#, ["{'a': 2} is not allowed"]),
    (#"{"enum":["a","b"]}"#, #""c""#, ["'c' is not allowed"]),
    (#"{"enum":["a",1]}"#, "true", ["true is not allowed"]),
    (#"{"minimum":1}"#, "0", ["0 is less than the minimum of 1"]),
    (#"{"minimum":1}"#, "0.5", ["0.5 is less than the minimum of 1"]),
    (#"{"minimum":-1}"#, "-2", ["-2 is less than the minimum of -1"]),
    (#"{"minItems":1}"#, "[]", ["[] is too short (at least 1 items)"]),
    (#"{"uniqueItems":true}"#, "[1,1.0]", ["[1, 1.0] has non-unique elements"]),
    (#"{"uniqueItems":true}"#, #"["a","b","a"]"#, ["['a', 'b', 'a'] has non-unique elements"]),
    (
      #"{"uniqueItems":true}"#,
      #"[{"a":1,"b":2},{"b":2,"a":1}]"#,
      ["[{'a': 1, 'b': 2}, {'b': 2, 'a': 1}] has non-unique elements"],
    ),
    (#"{"not":{"const":"x"}}"#, #""x""#, ["'x' is not allowed"]),
    (
      #"{"oneOf":[{"type":"string"},{"type":"integer"}]}"#,
      "true",
      ["true is not allowed"],
    ),
    (
      #"{"oneOf":[{"type":"number"},{"type":"integer"}]}"#,
      "1",
      ["1 is not allowed"],
    ),
    (
      #"{"anyOf":[{"type":"string"},{"type":"integer"}]}"#,
      "null",
      ["null is not allowed"],
    ),
    (
      #"{"allOf":[{"type":"integer"},{"minimum":5}]}"#,
      "1.5",
      ["1.5 is not of type 'integer'", "1.5 is less than the minimum of 5"],
    ),
    (
      #"{"if":{"type":"string"},"then":{"minLength":2},"else":{"minimum":2}}"#,
      #""a""#,
      ["'a' is too short (at least 2 characters)"],
    ),
    (
      #"{"if":{"type":"string"},"then":{"minLength":2},"else":{"minimum":2}}"#,
      "1",
      ["1 is less than the minimum of 2"],
    ),
    (
      #"{"propertyNames":{"pattern":"^[a-z]+$"}}"#,
      #"{"ok":1,"Bad":2}"#,
      ["'Bad' is not allowed"],
    ),
    (
      #"{"properties":{"groups":{"propertyNames":{"pattern":"^[a-z]+$"}}}}"#,
      #"{"groups":{"Bad":2}}"#,
      ["'Bad' is not allowed at groups"],
    ),
    (#"{"format":"date"}"#, #""2026-02-30""#, ["'2026-02-30' is not a 'date'"]),
    (#"{"format":"date"}"#, #""yesterday""#, ["'yesterday' is not a 'date'"]),
    (
      ##"{"$ref":"#/$defs/n","$defs":{"n":{"type":"integer"}}}"##,
      #""x""#,
      ["'x' is not of type 'integer'"],
    ),
    (
      ##"{"properties":{"a":{"$ref":"#/$defs/s"}},"$defs":{"s":{"type":"string","minLength":2}}}"##,
      #"{"a":""}"#,
      ["'' is too short (at least 2 characters) at a"],
    ),
    (#"{"properties":{"a":false}}"#, #"{"a":1}"#, ["1 is not allowed at a"]),
    (
      """
      {"type":"object","properties":{"a":{"type":"string"},"b":{"type":"string"}},\
      "required":["c"]}
      """,
      #"{"b":2,"a":1}"#,
      [
        "'c' is a required property",
        "1 is not of type 'string' at a",
        "2 is not of type 'string' at b",
      ],
    ),
  ])
  func `a value that breaks the schema says how`(
    schema: String,
    value: String,
    expected: [String],
  ) throws {
    let checker = try SchemaChecker(schema: authored(schema))

    #expect(try checker.check(authored(value)).map(\.description) == expected)
  }

  @Test
  func `annotation keywords are read and change nothing`() throws {
    let schema = JSONMembers([
      "title": #""t""#,
      "description": #""d""#,
      "default": "1",
      "$schema": #""https://json-schema.org/draft/2020-12/schema""#,
    ])
    let checker = try SchemaChecker(schema: authored(schema.json))

    #expect(try checker.check(authored("1")).isEmpty)
    #expect(try checker.check(authored(#""text""#)).isEmpty)
  }

  @Test
  func `a pattern ending in a line break guard refuses a name that ends in a line break`() throws {
    let schema = JSONMembers(["pattern": "\"\(Self.lineBreakGuard)\""])
    let checker = try SchemaChecker(schema: authored(schema.json))

    #expect(try checker.check(authored(#""calc""#)).isEmpty)
    #expect(try checker.check(authored(#""calc\n""#)).map(\.description) == [
      "'calc\\n' is not allowed",
    ])
  }

  @Test
  func `an index is sorted as a number, so 2 comes before 10`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"items":{"type":"string"}}"#))
    let value = try authored(#"["a","b",2,"d","e","f","g","h","i","j",10,"l"]"#)

    let failures = checker.check(value)

    #expect(failures.map(\.pathText) == ["2", "10"])
  }

  @Test
  func `the same value gives the same failures every time`() throws {
    let checker = try SchemaChecker(schema: authored(
      #"{"properties":{"a":{"type":"string"},"b":{"type":"string"},"c":{"type":"string"}}}"#,
    ))
    let value = try authored(#"{"c":3,"a":1,"b":2}"#)

    let first = checker.check(value)

    #expect(first.map(\.pathText) == ["a", "b", "c"])
    #expect(checker.check(value) == first)
  }

  @Test
  func `two branches that give the same failure give it once`() throws {
    let checker = try SchemaChecker(schema: authored(
      #"{"allOf":[{"type":"string"},{"type":"string"}]}"#,
    ))

    #expect(try checker.check(authored("1")).count == 1)
  }

  @Test(arguments: [
    ("1.5", false),
    ("2", true),
    ("2.0", true),
  ])
  func `a number with no fractional part is an integer, as Draft 2020-12 says`(
    value: String,
    isValid: Bool,
  ) throws {
    let checker = try SchemaChecker(schema: authored(#"{"type":"integer"}"#))

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `a number that is not finite is not an integer`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"type":"integer"}"#))

    #expect(checker.check(.number(.infinity)).count == 1)
    #expect(checker.check(.number(.nan)).count == 1)
  }
}
