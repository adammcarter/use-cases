import Testing
@testable import UseCasesCore

struct YAMLReadingErrorDiagnosticTests {
  private func refusal(_ text: String) throws -> YAMLReadingError {
    do {
      _ = try StrictYAMLReader().read(
        text,
        file: "a.yml",
        kind: .useCase,
      )
    } catch {
      return error
    }

    throw LoadFailure(message: "the text was read")
  }

  @Test
  func `the diagnostic names the file and the line without repeating them in the message`()
    throws
  {
    let error = try refusal("a: 1\nb: 2\nb: 3\n")
    let diagnostic = try error.diagnostic(in: workspacePath("use-cases/a.yml"))

    #expect(diagnostic.file.text == "use-cases/a.yml")
    #expect(diagnostic.position?.line == error.line)
    #expect(diagnostic.message == "duplicate key 'b'")
    #expect(diagnostic.severity == .error)
  }

  @Test(arguments: [
    ("a: 1\n---\nb: 2\n", "multiple-documents"),
    ("a: !!str 1\n", "tagged-value"),
    ("a: [\n", "not-yaml"),
    ("a: *nowhere\n", "undefined-alias"),
    ("a: on\n", "unquoted-text"),
    ("a: x # note\n", "text-cut-by-comment"),
    ("? [a]\n: 1\n", "unusable-key"),
    (String(repeating: "[", count: 70), "limit-exceeded"),
  ])
  func `each kind of refusal has its own code`(
    text: String,
    code: String,
  ) throws {
    let error = try refusal(text)
    let diagnostic = try error.diagnostic(in: workspacePath("a.yml"))

    #expect(diagnostic.code.text == code)
  }

  @Test
  func `a diagnostic reads as the file, the line and what is wrong`() throws {
    let error = try refusal("a: 1\na: 2\n")
    let diagnostic = try error.diagnostic(in: workspacePath("x/a.yml"))

    #expect(diagnostic
      .description == "x/a.yml:\(diagnostic.position?.line ?? 0): duplicate key 'a'")
  }
}
