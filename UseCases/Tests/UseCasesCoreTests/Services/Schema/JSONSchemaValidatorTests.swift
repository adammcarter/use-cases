import Testing
@testable import UseCasesCore

struct JSONSchemaValidatorTests {
  private static let schema = """
  {
    "type": "object",
    "additionalProperties": false,
    "required": ["step"],
    "properties": {
      "step": {"type": "string", "enum": ["run", "start"]},
      "only": {"type": "array", "items": {"type": "string"}},
      "page_size": {"type": "integer"},
      "dry_run": {"type": "boolean"}
    }
  }
  """

  private func validator() throws -> JSONSchemaValidator {
    try JSONSchemaValidator(schemaText: Self.schema)
  }

  @Test(arguments: [
    #"{"step": "run"}"#,
    #"{"step": "start", "only": ["a", "b"], "page_size": 5, "dry_run": true}"#,
    #"{"step": "run", "page_size": 5.0}"#,
    #"{"step": "run", "only": []}"#,
  ])
  func `a document that keeps the schema has no problems`(document: String) throws {
    #expect(try validator().problems(in: document).isEmpty)
  }

  @Test
  func `a member the schema requires and the document lacks is missing`() throws {
    #expect(try validator().problems(in: "{}") == [.missing(path: "", member: "step")])
  }

  @Test
  func `a member the schema does not list is unexpected, all of them together`() throws {
    let problems = try validator().problems(in: #"{"step": "run", "shell": "x", "extra": 1}"#)

    #expect(problems == [.unexpected(path: "", members: ["shell", "extra"])])
  }

  @Test
  func `a value of the wrong type breaks type, where it is`() throws {
    let problems = try validator()
      .problems(in: #"{"step": "run", "only": ["a", 2], "page_size": "5"}"#)

    #expect(problems.count == 2)
    #expect(problems.contains(.breaks(
      path: "only/1",
      keyword: "type",
      message: "2 is not of type 'string'",
    )))
    #expect(problems.contains(.breaks(
      path: "page_size",
      keyword: "type",
      message: "'5' is not of type 'integer'",
    )))
  }

  @Test
  func `a value outside an enum breaks enum, which the caller may choose to leave to someone else`(
  ) throws {
    let problems = try validator().problems(in: #"{"step": "walk"}"#)

    #expect(problems.map(\.keyword) == ["enum"])
  }

  @Test(arguments: ["", "{", "[1,", #"{"a": 1, "a": 2}"#, "nope"])
  func `text that is not one JSON document is unreadable`(text: String) throws {
    let problems = try validator().problems(in: text)

    #expect(problems.count == 1)
    guard case .unreadable = problems[0] else {
      Issue.record("expected unreadable, got \(problems)")
      return
    }
  }

  @Test
  func `a schema that is not JSON is refused`() {
    #expect(throws: JSONSchemaValidatorError.self) {
      try JSONSchemaValidator(schemaText: "{")
    }
  }

  @Test
  func `a schema with a keyword the checker does not know is refused, never skipped`() {
    #expect(throws: JSONSchemaValidatorError.self) {
      try JSONSchemaValidator(schemaText: #"{"type": "object", "examples": []}"#)
    }
  }
}

private extension JSONSchemaProblem {
  var keyword: String? {
    if case let .breaks(_, keyword, _) = self {
      return keyword
    }

    return nil
  }
}
