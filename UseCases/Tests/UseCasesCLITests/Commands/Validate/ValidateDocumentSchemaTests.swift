import Foundation
import Testing
@testable import UseCasesCLI

struct ValidateDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-validate.schema.json"

  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
    try workspace.folder.write("src/a.swift", "// @use-case:BAD\n")
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test
  func `the validate document follows the published schema`() async throws {
    let document = try await workspace.run(["--json", "validate"]).document()

    #expect(try failures(of: document) == [])
  }

  @Test
  func `the document has warnings and files to check, so the schema check is not empty`()
    async throws
  {
    let document = try await workspace.run(["--json", "validate"]).document()

    guard case let .array(files)? = document["files"],
          case let .array(warnings)? = document["warnings"]
    else {
      Issue.record("not a validate document")
      return
    }

    #expect(files.count == 3)
    #expect(warnings.count == 1)
  }

  @Test
  func `a refusal is a document of the error schema`() async throws {
    try workspace.folder.write("use-cases/broken.yml", "use_cases: 5\n")
    let result = await workspace.run(["--json", "validate"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails a document that breaks the schema`() async throws {
    let document = try await workspace.run(["--json", "validate"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["valid"] = .boolean(false)
    members["use_cases"] = .integer(-1)
    members["files"] = .array([.string("/etc/passwd")])
    members["warnings"] = .array([.string("")])
    members["stray"] = .integer(1)
    members["output_version"] = .integer(2)

    let broken = try failures(of: .object(members))

    #expect(broken.count >= 6)
  }
}
