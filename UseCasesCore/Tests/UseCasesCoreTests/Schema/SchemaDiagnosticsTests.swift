import Testing
@testable import UseCasesCore

/// A raw schema violation says which RULE broke; a diagnostic has to say which
/// FIELD broke, in which row, under a stable code. That translation is frozen
/// contract — the codes are published in docs/reference/error-codes.md and the
/// message shape is what a reader with 36 rows across 3 files actually reads.
struct SchemaDiagnosticsTests {
  private func diagnostics(
    _ violations: [SchemaViolation],
    sourcePath: String? = nil,
    document: JSONValue = .null,
  ) -> [Diagnostic] {
    SchemaDiagnostics.map(violations, sourcePath: sourcePath, document: document)
  }

  private func violation(
    keyword: String,
    instancePath: String = "",
    message: String = "broken",
    missingProperty: String? = nil,
    allowedValues: [JSONValue]? = nil,
  ) -> SchemaViolation {
    SchemaViolation(
      keyword: keyword,
      instancePath: instancePath,
      message: message,
      missingProperty: missingProperty,
      allowedValues: allowedValues,
    )
  }

  @Test(arguments: [
    ("additionalProperties", "additional_property"),
    ("enum", "enum.invalid_value"),
    ("const", "enum.invalid_value"),
    ("type", "schema.type"),
    ("pattern", "schema.pattern"),
    ("minLength", "schema.minLength"),
    ("oneOf", "schema.oneOf"),
    ("if", "schema.if"),
    ("not", "schema.not"),
    ("dependentRequired", "schema.dependentRequired"),
  ])
  func `a keyword maps to its frozen code`(
    keyword: String,
    expected: String,
  ) {
    #expect(diagnostics([violation(keyword: keyword)]).first?.code == expected)
  }

  @Test(arguments: [
    ("schema_version", "schema_version.required"),
    ("observable_outcomes", "use_case.observable_outcomes.required"),
    ("approval_policy", "approval_policy.required"),
    ("title", "title.required"),
    ("id", "id.required"),
  ])
  func `a missing property maps to its own required code`(
    property: String,
    expected: String,
  ) {
    let found = diagnostics([
      violation(
        keyword: "required",
        message: "must have required property '\(property)'",
        missingProperty: property,
      ),
    ])

    #expect(found.first?.code == expected)
  }

  @Test
  func `a required message names the property once, not twice`() {
    let found = diagnostics([
      violation(
        keyword: "required",
        instancePath: "/use_cases/0",
        message: "must have required property 'title'",
        missingProperty: "title",
      ),
    ])

    #expect(found.first?.message == "title: must have required property 'title'")
  }

  @Test
  func `a message names the field taken from the pointer`() {
    let found = diagnostics([
      violation(
        keyword: "type",
        instancePath: "/use_cases/3/value_tier",
        message: "must be string",
      ),
    ])

    #expect(found.first?.message == "value_tier: must be string")
  }

  @Test
  func `an array index is skipped when naming the field`() {
    let found = diagnostics([
      violation(keyword: "type", instancePath: "/use_cases/3", message: "must be object"),
    ])

    #expect(found.first?.message == "use_cases: must be object")
  }

  @Test
  func `a root level violation is not prefixed at all`() {
    let found = diagnostics([violation(keyword: "type", message: "must be object")])

    #expect(found.first?.message == "must be object")
  }

  @Test
  func `an enum message lists the values that were allowed`() {
    let found = diagnostics([
      violation(
        keyword: "enum",
        instancePath: "/use_cases/0/value_tier",
        message: "must be equal to one of the allowed values",
        allowedValues: [.string("critical"), .string("core")],
      ),
    ])

    #expect(
      found.first?.message
        == "value_tier: must be equal to one of the allowed values (allowed: critical, core)",
    )
  }

  @Test
  func `an enum with no listed values keeps the bare message`() {
    let found = diagnostics([
      violation(
        keyword: "enum",
        message: "must be equal to one of the allowed values",
        allowedValues: [],
      ),
    ])

    #expect(found.first?.message == "must be equal to one of the allowed values")
  }

  @Test
  func `the pointer rides along, and an empty pointer becomes null`() {
    let found = diagnostics([
      violation(keyword: "type", instancePath: "/a/b"),
      violation(keyword: "type", instancePath: ""),
    ])

    #expect(found[0].jsonPointer == "/a/b")
    #expect(found[1].jsonPointer == nil)
  }

  @Test
  func `the source path rides along untouched`() {
    let found = diagnostics([violation(keyword: "type")], sourcePath: "use-cases/x.yml")

    #expect(found.first?.sourcePath == "use-cases/x.yml")
  }

  @Test
  func `every schema diagnostic is an error with no related ids`() {
    let found = diagnostics([violation(keyword: "type")])

    #expect(found.first?.severity == .error)
    #expect(found.first?.relatedIdentifiers.isEmpty == true)
  }

  @Test
  func `a row's id is resolved from the document for its pointer`() throws {
    let document = try JSONParser.parse(
      #"{"use_cases":[{"id":"a.one"},{"id":"a.two"}]}"#,
    )
    let found = diagnostics(
      [
        violation(keyword: "type", instancePath: "/use_cases/1/title"),
        violation(keyword: "type", instancePath: "/use_cases/0"),
      ],
      document: document,
    )

    #expect(found[0].entityIdentifier == "a.two")
    #expect(found[1].entityIdentifier == "a.one")
  }

  @Test
  func `a pointer outside the rows resolves no row id`() throws {
    let document = try JSONParser.parse(#"{"use_cases":[{"id":"a.one"}]}"#)
    let found = diagnostics(
      [
        violation(keyword: "type", instancePath: "/feature/id"),
        violation(keyword: "type", instancePath: ""),
        violation(keyword: "type", instancePath: "/use_cases"),
      ],
      document: document,
    )

    #expect(found.allSatisfy { $0.entityIdentifier == nil })
  }

  @Test
  func `a row without a string id resolves no row id`() throws {
    let document = try JSONParser.parse(#"{"use_cases":[{"id":7},{}]}"#)
    let found = diagnostics(
      [
        violation(keyword: "type", instancePath: "/use_cases/0/title"),
        violation(keyword: "type", instancePath: "/use_cases/1/title"),
        violation(keyword: "type", instancePath: "/use_cases/9/title"),
      ],
      document: document,
    )

    #expect(found.allSatisfy { $0.entityIdentifier == nil })
  }

  @Test
  func `a document that is not a record resolves no row id`() {
    let found = diagnostics(
      [violation(keyword: "type", instancePath: "/use_cases/0/title")],
      document: .array([]),
    )

    #expect(found.first?.entityIdentifier == nil)
  }
}
