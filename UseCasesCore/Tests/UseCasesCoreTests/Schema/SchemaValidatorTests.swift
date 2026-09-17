import Testing
@testable import UseCasesCore

/// The validator is a port of AJV's behaviour, driven by the 27 schema files
/// (ADR 0007 decision 7). Everything it emits is frozen contract: the codes, the
/// messages, the pointers, the entity ids and the ORDER the diagnostics arrive
/// in. The golden corpus is the TypeScript's own output, so these tests fail the
/// moment the port stops agreeing with the tool being replaced.
struct SchemaValidatorTests {
  private func violations(
    _ schemaText: String,
    _ documentText: String,
  ) throws -> [SchemaViolation] {
    let registry = try SchemaFixtures.registry()
    let validator = SchemaValidator(registry: registry)
    return try validator.violations(
      for: JSONParser.parse(documentText),
      against: JSONParser.parse(schemaText),
    )
  }

  @Test(arguments: SchemaGoldenCorpus.caseNames)
  func `reproduces the TypeScript diagnostics exactly`(name: String) throws {
    let golden = try SchemaFixtures.goldenCase(named: name)
    let registry = try SchemaFixtures.registry()

    let result = try registry.validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: golden.schemaFile),
      value: JSONParser.parse(golden.document),
      sourcePath: golden.sourcePath,
    )

    #expect(result.isValid == golden.isValid)
    #expect(result.diagnostics.count == golden.diagnostics.count)

    for (index, expected) in golden.diagnostics.enumerated()
      where index < result.diagnostics.count
    {
      let actual = result.diagnostics[index]
      #expect(actual.code == expected.code, "\(name) #\(index) code")
      #expect(actual.severity.rawValue == expected.severity, "\(name) #\(index) severity")
      #expect(actual.message == expected.message, "\(name) #\(index) message")
      #expect(actual.sourcePath == expected.sourcePath, "\(name) #\(index) source_path")
      #expect(actual.jsonPointer == expected.jsonPointer, "\(name) #\(index) json_pointer")
      #expect(actual.entityIdentifier == expected.entityIdentifier, "\(name) #\(index) entity_id")
      #expect(
        actual.relatedIdentifiers == expected.relatedIdentifiers,
        "\(name) #\(index) related_ids",
      )
    }
  }

  @Test
  func `a string length counts code points, not characters or utf16 units`() throws {
    let schema = #"{"type":"string","minLength":2}"#

    #expect(try violations(schema, #""😀""#).map(\.keyword) == ["minLength"])
    #expect(try violations(schema, #""é""#).isEmpty)
    #expect(try violations(schema, #""ab""#).isEmpty)
  }

  @Test
  func `an integer type accepts a whole double and refuses a fraction`() throws {
    #expect(try violations(#"{"type":"integer"}"#, "2.0").isEmpty)
    #expect(try violations(#"{"type":"integer"}"#, "2.5").map(\.message) == ["must be integer"])
  }

  @Test
  func `a union type names both members in the message`() throws {
    let found = try violations(#"{"type":["string","null"]}"#, "3")

    #expect(found.map(\.message) == ["must be string,null"])
  }

  @Test
  func `a wrong type still reports the untyped keywords beside it`() throws {
    let found = try violations(#"{"type":"string","enum":["a"]}"#, "5")

    #expect(found.map(\.keyword) == ["type", "enum"])
  }

  @Test
  func `a wrong type skips the keywords of that type`() throws {
    let found = try violations(#"{"type":"string","minLength":3}"#, "5")

    #expect(found.map(\.keyword) == ["type"])
  }

  @Test
  func `duplicate items are reported as the last pair scanned`() throws {
    let schema = #"{"type":"array","uniqueItems":true}"#

    #expect(
      try violations(schema, "[1,1,1]").map(\.message)
        == ["must NOT have duplicate items (items ## 1 and 2 are identical)"],
    )
    #expect(
      try violations(schema, #"[{"a":1,"b":2},{"b":2,"a":1}]"#).map(\.message)
        == ["must NOT have duplicate items (items ## 0 and 1 are identical)"],
    )
    #expect(try violations(schema, "[1,2,3]").isEmpty)
    #expect(try violations(schema, "[]").isEmpty)
  }

  @Test
  func `additional properties are reported in the order the data lists them`() throws {
    let schema = #"{"type":"object","properties":{"a":{}},"additionalProperties":false}"#
    let found = try violations(schema, #"{"z":1,"y":2,"a":3}"#)

    #expect(found.count == 2)
    #expect(
      found.allSatisfy { violation in
        violation.message == "must NOT have additional properties"
      },
    )
    #expect(found.map(\.instancePath) == ["", ""])
  }

  @Test
  func `properties are visited in the order the schema declares them`() throws {
    let schema = #"""
    {"type":"object","properties":{"b":{"type":"string"},"a":{"type":"string"}}}
    """#
    let found = try violations(schema, #"{"a":1,"b":2}"#)

    #expect(found.map(\.instancePath) == ["/b", "/a"])
  }

  @Test
  func `required properties are reported in the order the schema lists them`() throws {
    let schema = #"""
    {"type":"object","properties":{"a":{},"b":{},"c":{}},"required":["c","a","b"]}
    """#
    let found = try violations(schema, "{}")

    #expect(found.map(\.missingProperty) == ["c", "a", "b"])
  }

  @Test
  func `an instance path escapes a slash and a tilde`() throws {
    let schema = #"{"type":"object","properties":"#
      + #"{"a/b":{"type":"string"},"c~d":{"type":"string"}}}"#
    let found = try violations(schema, #"{"a/b":1,"c~d":2}"#)

    #expect(found.map(\.instancePath) == ["/a~1b", "/c~0d"])
  }

  @Test
  func `a boolean schema passes everything or nothing`() throws {
    let schema = #"{"type":"object","properties":{"yes":true,"no":false}}"#

    #expect(try violations(schema, #"{"yes":1}"#).isEmpty)
    #expect(try violations(schema, #"{"no":1}"#).count == 1)
  }

  @Test
  func `a reference is validated alongside its sibling keywords`() throws {
    let schema = #"""
    {"type":"string","$defs":{"s":{"type":"string"}},"$ref":"#/$defs/s","minLength":5}
    """#
    let found = try violations(schema, #""abc""#)

    #expect(found.map(\.keyword) == ["minLength"])
  }

  @Test
  func `a reference into another schema file resolves`() throws {
    let schema = #"{"$ref":"https://use-cases.dev/schemas/v1/common.schema.json#/$defs/id"}"#

    #expect(try violations(schema, #""a.b""#).isEmpty)
    #expect(try violations(schema, #""A.B""#).map(\.keyword) == ["pattern"])
  }

  @Test
  func `anyOf keeps every branch error beside its own`() throws {
    let schema = #"{"anyOf":[{"type":"string"},{"type":"number"}]}"#
    let found = try violations(schema, "{}")

    #expect(found.map(\.keyword) == ["type", "type", "anyOf"])
    #expect(found.last?.message == "must match a schema in anyOf")
  }

  @Test
  func `anyOf reports nothing once a branch passes`() throws {
    let schema = #"{"anyOf":[{"type":"string"},{"type":"number"}]}"#

    #expect(try violations(schema, "1").isEmpty)
  }

  @Test
  func `oneOf refuses a value that matches two branches`() throws {
    let schema = #"{"oneOf":[{"type":"object"},{"type":"object"}]}"#
    let found = try violations(schema, "{}")

    #expect(found.map(\.message) == ["must match exactly one schema in oneOf"])
  }

  @Test
  func `oneOf keeps the branch errors when nothing matches`() throws {
    let schema = #"{"oneOf":[{"type":"string"},{"type":"number"}]}"#
    let found = try violations(schema, "{}")

    #expect(found.map(\.keyword) == ["type", "type", "oneOf"])
  }

  @Test
  func `not swallows the errors of the schema it negates`() throws {
    let schema = #"{"not":{"anyOf":[{"pattern":"^/"},{"pattern":"\\.\\."}],"type":"string"}}"#

    #expect(try violations(schema, #""ok/rel""#).isEmpty)
    #expect(try violations(schema, #""/abs""#).map(\.message) == ["must NOT be valid"])
  }

  @Test
  func `then only runs when if matches`() throws {
    let schema = #"""
    {"type":"object","properties":{"a":{},"b":{}},
     "if":{"properties":{"a":{"const":1}},"required":["a"]},
     "then":{"properties":{"b":{}},"required":["b"]}}
    """#

    #expect(try violations(schema, #"{"a":2}"#).isEmpty)
    #expect(
      try violations(schema, #"{"a":1}"#).map(\.keyword) == ["required", "if"],
    )
    #expect(try violations(schema, #"{"a":1,"b":2}"#).isEmpty)
  }

  @Test
  func `property names are checked once per offending key`() throws {
    let schema = #"{"type":"object","propertyNames":{"pattern":"^[a-z]+$"}}"#
    let found = try violations(schema, #"{"A":1,"B":2,"ok":3}"#)

    #expect(found.map(\.keyword) == ["pattern", "propertyNames", "pattern", "propertyNames"])
    #expect(found.map(\.instancePath) == ["", "", "", ""])
  }

  @Test
  func `array items report the index that broke`() throws {
    let schema = #"{"type":"array","items":{"type":"string"}}"#
    let found = try violations(schema, #"[1,"a",2]"#)

    #expect(found.map(\.instancePath) == ["/0", "/2"])
  }

  @Test
  func `a constant compares deeply`() throws {
    let schema = #"{"const":{"a":1}}"#

    #expect(try violations(schema, #"{"a":1}"#).isEmpty)
    #expect(try violations(schema, #"{"a":2}"#).map(\.message) == ["must be equal to constant"])
  }

  @Test
  func `an exclusive minimum refuses its own boundary`() throws {
    let schema = #"{"type":"number","exclusiveMinimum":0}"#

    #expect(try violations(schema, "0").map(\.message) == ["must be > 0"])
    #expect(try violations(schema, "0.5").isEmpty)
    #expect(try violations(#"{"type":"number","minimum":1}"#, "1").isEmpty)
    #expect(try violations(#"{"type":"integer","minimum":1}"#, "0")
      .map(\.message) == ["must be >= 1"])
  }

  @Test
  func `an end anchored pattern refuses a trailing newline, as ECMAScript does`() throws {
    let schema = #"{"type":"string","pattern":"^[a-z]+$"}"#

    #expect(try violations(schema, #""abc""#).isEmpty)
    #expect(try violations(schema, #""abc\n""#).map(\.keyword) == ["pattern"])
  }

  @Test
  func `an unanchored pattern may match anywhere in the string`() throws {
    let schema = #"{"type":"string","pattern":"#
      + #""(^|/)\\.\\.(/|$)"}"#

    #expect(try violations(schema, #""a/../b""#).isEmpty)
    #expect(try violations(schema, #""a/b""#).map(\.keyword) == ["pattern"])
  }

  @Test
  func `a schema using a keyword the validator does not implement fails to compile`() throws {
    let registry = try SchemaFixtures.registry()
    let validator = SchemaValidator(registry: registry)
    let schema = try JSONParser.parse(#"{"type":"string","maxLength":3}"#)

    let problem = validator.compilationProblem(in: schema, root: schema)

    #expect(problem?.contains("maxLength") == true)
  }

  @Test
  func `a schema whose reference leads nowhere fails to compile`() throws {
    let registry = try SchemaFixtures.registry()
    let validator = SchemaValidator(registry: registry)
    let schema = try JSONParser.parse(##"{"$ref":"#/$defs/missing"}"##)

    let problem = validator.compilationProblem(in: schema, root: schema)

    #expect(problem?.contains("unresolved $ref") == true)
  }

  @Test
  func `every published schema compiles`() throws {
    let registry = try SchemaFixtures.registry()
    let validator = SchemaValidator(registry: registry)

    for identifier in SchemaRegistry.publicSchemaIdentifiers {
      let schema = try #require(registry.schema(withIdentifier: identifier))
      #expect(validator.compilationProblem(in: schema, root: schema) == nil, "\(identifier)")
    }
  }

  @Test
  func `an empty schema accepts anything`() throws {
    for document in ["null", "1", #""a""#, "[]", "{}"] {
      #expect(try violations("{}", document).isEmpty)
    }
  }
}
