import Foundation
import Testing
@testable import UseCasesCore

/// The diagnostic wire shape is frozen by ADR 0007 decision 8. The nullable
/// fields are always PRESENT (as null) and `source_span` is OMITTED when absent —
/// Swift's synthesised encoder would drop all four, so encoding is explicit.
struct DiagnosticTests {
  private func encodeToObject(_ diagnostic: Diagnostic) throws -> [String: Any] {
    let encoder = JSONEncoder()
    let data = try encoder.encode(diagnostic)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
  }

  @Test
  func `the factory defaults severity to error`() {
    let diagnostic = Diagnostic(code: "workspace.not_found", message: "missing")
    #expect(diagnostic.severity == .error)
  }

  @Test
  func `the factory leaves the optional fields empty`() {
    let diagnostic = Diagnostic(code: "workspace.not_found", message: "missing")
    #expect(diagnostic.sourcePath == nil)
    #expect(diagnostic.jsonPointer == nil)
    #expect(diagnostic.sourceSpan == nil)
    #expect(diagnostic.entityIdentifier == nil)
    #expect(diagnostic.relatedIdentifiers.isEmpty)
  }

  @Test
  func `a nullable field encodes as null rather than being dropped`() throws {
    let object = try encodeToObject(Diagnostic(code: "a.b", message: "m"))

    #expect(object["source_path"] is NSNull)
    #expect(object["json_pointer"] is NSNull)
    #expect(object["entity_id"] is NSNull)
  }

  @Test
  func `an absent source span is omitted entirely`() throws {
    let object = try encodeToObject(Diagnostic(code: "a.b", message: "m"))

    #expect(object["source_span"] == nil)
  }

  @Test
  func `a present source span is encoded with line and column`() throws {
    let span = SourceSpan(
      start: SourcePosition(line: 3, column: 5),
      end: SourcePosition(line: 4, column: 1),
    )
    let diagnostic = Diagnostic(code: "a.b", message: "m", sourceSpan: span)

    let object = try encodeToObject(diagnostic)
    let encodedSpan = try #require(object["source_span"] as? [String: Any])
    let start = try #require(encodedSpan["start"] as? [String: Any])

    #expect(start["line"] as? Int == 3)
    #expect(start["column"] as? Int == 5)
  }

  @Test
  func `related identifiers encode as an array even when empty`() throws {
    let object = try encodeToObject(Diagnostic(code: "a.b", message: "m"))
    let related = try #require(object["related_ids"] as? [Any])

    #expect(related.isEmpty)
  }

  @Test
  func `every wire key uses the frozen snake case spelling`() throws {
    let diagnostic = Diagnostic(
      code: "a.b",
      message: "m",
      sourcePath: "use-cases.yml",
      entityIdentifier: "capsule.demos",
      relatedIdentifiers: ["x.y"],
    )
    let object = try encodeToObject(diagnostic)

    #expect(Set(object.keys) == [
      "code", "severity", "message", "source_path",
      "json_pointer", "entity_id", "related_ids",
    ])
  }

  @Test
  func `a diagnostic round trips through its own wire format`() throws {
    let original = Diagnostic(
      code: "workspace_config.schema_error",
      severity: .warning,
      message: "bad",
      sourcePath: "use-cases.yml",
      jsonPointer: "/data_root",
      entityIdentifier: "use-cases",
      relatedIdentifiers: ["a.b", "c.d"],
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Diagnostic.self, from: data)

    #expect(decoded == original)
  }

  @Test(arguments: [DiagnosticSeverity.info, .warning, .error])
  func `severity encodes as its lowercase name`(severity: DiagnosticSeverity) throws {
    let object = try encodeToObject(
      Diagnostic(code: "a.b", severity: severity, message: "m"),
    )

    #expect(object["severity"] as? String == severity.rawValue)
  }
}
