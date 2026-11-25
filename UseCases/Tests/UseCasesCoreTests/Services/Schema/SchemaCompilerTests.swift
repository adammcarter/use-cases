import Testing
@testable import UseCasesCore

struct SchemaCompilerTests {
  @Test(arguments: [
    #"{"maxProperties":1}"#,
    #"{"patternProperties":{}}"#,
    #"{"$id":"x"}"#,
    #"{"$comment":"x"}"#,
    #"{"examples":[]}"#,
    #"{"dependentSchemas":{}}"#,
    #"{"unevaluatedProperties":false}"#,
    #"{"contains":{}}"#,
    #"{"exclusiveMaximum":1}"#,
    #"{"multipleOf":2}"#,
    #"{"Type":"string"}"#,
  ])
  func `a keyword the checker does not support is refused at the top`(schema: String) throws {
    let value = try authored(schema)

    let error = #expect(throws: SchemaCompilerError.self) {
      try SchemaChecker(schema: value)
    }

    guard case let .unknownKeyword(_, location)? = error else {
      Issue.record("expected an unknown keyword, got \(String(describing: error))")
      return
    }
    #expect(location.isEmpty)
  }

  @Test(arguments: [
    (#"{"properties":{"a":{"maxProperties":1}}}"#, "maxProperties", "properties/a"),
    (#"{"items":{"nope":1}}"#, "nope", "items"),
    (#"{"additionalProperties":{"nope":1}}"#, "nope", "additionalProperties"),
    (#"{"propertyNames":{"nope":1}}"#, "nope", "propertyNames"),
    (#"{"not":{"nope":1}}"#, "nope", "not"),
    (#"{"allOf":[{},{"nope":1}]}"#, "nope", "allOf/1"),
    (#"{"anyOf":[{"nope":1}]}"#, "nope", "anyOf/0"),
    (#"{"oneOf":[{"nope":1}]}"#, "nope", "oneOf/0"),
    (#"{"if":{"nope":1}}"#, "nope", "if"),
    (#"{"then":{"nope":1}}"#, "nope", "then"),
    (#"{"else":{"nope":1}}"#, "nope", "else"),
    (#"{"$defs":{"d":{"nope":1}}}"#, "nope", "$defs/d"),
    (#"{"properties":{"a":{"$defs":{}}}}"#, "$defs", "properties/a"),
  ])
  func `a keyword it does not support is refused wherever it sits`(
    schema: String,
    keyword: String,
    location: String,
  ) throws {
    let value = try authored(schema)

    #expect(throws: SchemaCompilerError.unknownKeyword(keyword, location: location)) {
      try SchemaChecker(schema: value)
    }
  }

  @Test(arguments: [
    (#"{"type":"text"}"#, "type"),
    (#"{"type":[]}"#, "type"),
    (#"{"type":["text"]}"#, "type"),
    (#"{"type":["string",1]}"#, "type"),
    (#"{"type":1}"#, "type"),
    (#"{"$ref":1}"#, "$ref"),
    (#"{"required":"a"}"#, "required"),
    (#"{"required":[1]}"#, "required"),
    (#"{"minLength":-1}"#, "minLength"),
    (#"{"minLength":1.5}"#, "minLength"),
    (#"{"minLength":"1"}"#, "minLength"),
    (#"{"maxLength":-1}"#, "maxLength"),
    (#"{"minItems":-1}"#, "minItems"),
    (#"{"minimum":"1"}"#, "minimum"),
    (#"{"pattern":1}"#, "pattern"),
    (#"{"uniqueItems":1}"#, "uniqueItems"),
    (#"{"enum":"a"}"#, "enum"),
    (#"{"properties":[]}"#, "properties"),
    (#"{"$defs":[]}"#, "$defs"),
    (#"{"allOf":[]}"#, "allOf"),
    (#"{"anyOf":{}}"#, "anyOf"),
    (#"{"oneOf":[]}"#, "oneOf"),
  ])
  func `a keyword whose value is the wrong kind is refused`(
    schema: String,
    keyword: String,
  ) throws {
    let value = try authored(schema)

    #expect(throws: SchemaCompilerError.invalidKeywordValue(keyword, location: "")) {
      try SchemaChecker(schema: value)
    }
  }

  @Test(arguments: ["1", "\"x\"", "[]", "null"])
  func `a schema that is neither an object nor a boolean is refused`(schema: String) throws {
    let value = try authored(schema)

    #expect(throws: SchemaCompilerError.notASchema(location: "")) {
      try SchemaChecker(schema: value)
    }
  }

  @Test
  func `a subschema that is neither an object nor a boolean is refused where it sits`() throws {
    let value = try authored(#"{"properties":{"a":{"items":1}}}"#)

    #expect(throws: SchemaCompilerError.notASchema(location: "properties/a/items")) {
      try SchemaChecker(schema: value)
    }
  }

  @Test(arguments: [
    "#/$defs/missing",
    "#/definitions/n",
    "#",
    "other.json#/$defs/n",
    "#/$defs/",
    "#/$defs/n/properties",
    "n",
  ])
  func `a reference that names no definition is refused`(reference: String) throws {
    let schema = JSONMembers([
      "$ref": "\"\(reference)\"",
      "$defs": #"{"n":{}}"#,
    ])
    let value = try authored(schema.json)

    #expect(throws: SchemaCompilerError.unresolvedReference(reference)) {
      try SchemaChecker(schema: value)
    }
  }

  @Test
  func `a definition may refer to a definition written after it`() throws {
    let checker = try SchemaChecker(schema: authored(
      ##"{"$ref":"#/$defs/a","$defs":{"a":{"$ref":"#/$defs/b"},"b":{"type":"string"}}}"##,
    ))

    #expect(try checker.check(authored("1")).count == 1)
    #expect(try checker.check(authored(#""x""#)).isEmpty)
  }

  @Test(arguments: ["(", "[a", "a{2,1}"])
  func `a pattern that is not a regular expression is refused`(pattern: String) throws {
    let property = JSONMembers(["pattern": "\"\(pattern)\""])
    let properties = JSONMembers(["a": property.json])
    let value = try authored(JSONMembers(["properties": properties.json]).json)

    #expect(throws: SchemaCompilerError.invalidPattern(pattern, location: "properties/a")) {
      try SchemaChecker(schema: value)
    }
  }

  @Test(arguments: [
    (#"^\d+$"#, #"\d"#),
    (#"^\w+$"#, #"\w"#),
    (#"^\S*$"#, #"\S"#),
    (#"\bword"#, #"\b"#),
    (#"\p{L}"#, #"\p"#),
    ("(?i)abc", "(?i"),
    (#"abc\z"#, #"\z"#),
    ("[[:alpha:]]", "[ inside a character class"),
  ])
  func `a pattern whose syntax the two languages read differently is refused`(
    pattern: String,
    construct: String,
  ) {
    let schema = AuthoredValue.object([
      AuthoredMember(
        key: "pattern",
        value: .string(pattern),
      ),
    ])
    let expected = SchemaCompilerError.unsupportedPattern(
      pattern,
      construct: construct,
      location: "",
    )

    #expect(throws: expected) {
      try SchemaChecker(schema: schema)
    }
  }

  @Test(arguments: ["time", "email", "uri", "Date", ""])
  func `a format the checker does not enforce is refused`(format: String) throws {
    let value = try authored(JSONMembers(["format": "\"\(format)\""]).json)

    #expect(throws: SchemaCompilerError.unsupportedFormat(format, location: "")) {
      try SchemaChecker(schema: value)
    }
  }

  @Test(arguments: [
    "http://json-schema.org/draft-07/schema#",
    "https://json-schema.org/draft/2019-09/schema",
    "",
  ])
  func `a schema of another dialect is refused`(dialect: String) throws {
    let value = try authored(JSONMembers(["$schema": "\"\(dialect)\""]).json)

    #expect(throws: SchemaCompilerError.unsupportedDialect(dialect)) {
      try SchemaChecker(schema: value)
    }
  }

  @Test
  func `an object with nothing in it is a schema that accepts anything`() throws {
    let checker = try SchemaChecker(schema: authored("{}"))

    #expect(try checker.check(authored(#"[1,{"a":null}]"#)).isEmpty)
  }
}
