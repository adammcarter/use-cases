import Testing
@testable import UseCasesCore

/// Names in a schema and in a document are the same only when they are the same Unicode scalars.
struct SchemaCheckerExactTextTests {
  static let composed = "\u{E9}"
  static let decomposed = "e\u{301}"
  static let kelvin = "\u{212A}"

  private func object(_ pairs: KeyValuePairs<String, AuthoredValue>) -> AuthoredValue {
    var members: [AuthoredMember] = []
    for pair in pairs {
      members.append(AuthoredMember(
        key: pair.key,
        value: pair.value,
      ))
    }

    return .object(members)
  }

  @Test(arguments: [
    (SchemaCheckerExactTextTests.composed, SchemaCheckerExactTextTests.decomposed),
    (SchemaCheckerExactTextTests.decomposed, SchemaCheckerExactTextTests.composed),
    ("K", SchemaCheckerExactTextTests.kelvin),
    (SchemaCheckerExactTextTests.kelvin, "K"),
  ])
  func `a required name is met only by the same scalars`(
    required: String,
    present: String,
  ) throws {
    let schema = object(["required": .array([.string(required)])])
    let checker = try SchemaChecker(schema: schema)

    let failures = checker.check(object([present: .integer(1)]))

    #expect(failures.map(\.keyword) == [.required])
    #expect(checker.check(object([required: .integer(1)])).isEmpty)
  }

  @Test
  func `a listed property is matched only by the same scalars`() throws {
    let schema = object(["properties": object([
      SchemaCheckerExactTextTests.composed: object(["type": .string("string")]),
      SchemaCheckerExactTextTests.decomposed: object(["type": .string("integer")]),
    ])])
    let checker = try SchemaChecker(schema: schema)

    let composedFailures = checker
      .check(object([SchemaCheckerExactTextTests.composed: .integer(1)]))
    let decomposedFailures = checker
      .check(object([SchemaCheckerExactTextTests.decomposed: .string("x")]))

    #expect(composedFailures.map(\.message) == ["1 is not of type 'string'"])
    #expect(composedFailures.map(\.path) == [[.key(SchemaCheckerExactTextTests.composed)]])
    #expect(decomposedFailures.map(\.message) == ["'x' is not of type 'integer'"])
    #expect(decomposedFailures.map(\.path) == [[.key(SchemaCheckerExactTextTests.decomposed)]])
    #expect(checker.check(object([
      SchemaCheckerExactTextTests.composed: .string("x"),
      SchemaCheckerExactTextTests.decomposed: .integer(1),
    ])).isEmpty)
  }

  @Test(arguments: [
    (SchemaCheckerExactTextTests.composed, SchemaCheckerExactTextTests.decomposed),
    (SchemaCheckerExactTextTests.decomposed, SchemaCheckerExactTextTests.composed),
    ("K", SchemaCheckerExactTextTests.kelvin),
  ])
  func `a name that only looks like a listed one is an additional property`(
    listed: String,
    written: String,
  ) throws {
    let schema = object([
      "properties": object([listed: object([:])]),
      "additionalProperties": .boolean(false),
    ])
    let checker = try SchemaChecker(schema: schema)

    let failures = checker.check(object([written: .integer(1)]))

    #expect(failures.map(\.keyword) == [.additionalProperties])
    #expect(checker.check(object([listed: .integer(1)])).isEmpty)
  }

  @Test
  func `additional properties that only look alike each fail at their own path`() throws {
    let schema = object(["additionalProperties": object(["type": .string("string")])])
    let checker = try SchemaChecker(schema: schema)

    let failures = checker.check(object([
      SchemaCheckerExactTextTests.composed: .integer(1),
      SchemaCheckerExactTextTests.decomposed: .integer(1),
    ]))

    #expect(failures.count == 2)
    #expect(failures.map(\.path) == [
      [.key(SchemaCheckerExactTextTests.decomposed)],
      [.key(SchemaCheckerExactTextTests.composed)],
    ])
  }

  @Test
  func `a definition is found only by the same scalars`() throws {
    let schema = object([
      "$ref": .string("#/$defs/\(SchemaCheckerExactTextTests.composed)"),
      "$defs": object([SchemaCheckerExactTextTests
          .decomposed: object(["type": .string("string")])]),
    ])

    #expect(throws: SchemaCompilerError
      .unresolvedReference("#/$defs/\(SchemaCheckerExactTextTests.composed)"))
    {
      try SchemaChecker(schema: schema)
    }
  }
}
