import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct HooksDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-hooks.schema.json"

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
    try place.folder.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    try place.folder.write(".git/HEAD", "ref: refs/heads/main\n")
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    ["--json", "hooks"],
    ["--json", "hooks", "add", "commit"],
    ["--json", "hooks", "add", "commit", "push", "--dry-run"],
    ["--json", "hooks", "remove", "push"],
  ])
  func `the hooks document of every request follows the published schema`(
    arguments: [String],
  ) async throws {
    let result = await place.run(
      arguments,
      hooks: place.clone(),
    )

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `a document with notes and a hook manager follows it too`() async throws {
    let result = await place.run(
      ["--json", "hooks", "add", "commit"],
      hooks: place.clone(isManaged: true),
    )

    #expect(result.exitCode == 1)
    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails a hooks document that breaks the schema`() async throws {
    let document = try await place.run(
      ["--json", "hooks"],
      hooks: place.clone(),
    ).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["changed"] = .array([.string("pre-commit")])

    #expect(try !failures(of: .object(members)).isEmpty)
  }

  @Test
  func `a refusal to hooks is a document of the error schema`() async throws {
    let result = await place.run(
      ["--json", "hooks", "add", "merge"],
      hooks: place.clone(),
    )
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }
}
