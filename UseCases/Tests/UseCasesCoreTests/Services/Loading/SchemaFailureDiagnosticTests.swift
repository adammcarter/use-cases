import Testing
@testable import UseCasesCore

struct SchemaFailureDiagnosticTests {
  private func failures(_ json: String) throws -> [SchemaFailure] {
    try BundledSchemaLoader().loadChecker(for: .useCases).check(authored(json))
  }

  @Test
  func `a failure becomes an unlocated error in the file saying where the value is`() throws {
    let found = try failures(#"{"use_cases":[{"id":"a","title":42}]}"#)
    let failure = try #require(found.first)

    let diagnostic = try failure.diagnostic(in: workspacePath("use-cases/a.yml"))

    #expect(diagnostic.file.text == "use-cases/a.yml")
    #expect(diagnostic.position == nil)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.code.text == "schema-type")
    #expect(diagnostic.message == "42 is not of type 'string' at use_cases/0/title")
  }

  @Test
  func `the code carries the keyword that failed`() throws {
    let found = try failures(#"{"use_cases":[{"id":"a","title":"t","x":1}]}"#)
    let failure = try #require(found.first)

    let diagnostic = try failure.diagnostic(in: workspacePath("a.yml"))

    #expect(diagnostic.code.text == "schema-additionalProperties")
  }
}
