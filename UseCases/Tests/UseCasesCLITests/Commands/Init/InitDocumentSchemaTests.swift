import Foundation
import Testing
@testable import UseCasesCLI

struct InitDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-init.schema.json"

  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    ["--json", "init"],
    ["--json", "init", "--minimal"],
    ["--json", "init", "--prefix", "shop"],
    ["--json", "init", "--dry-run"],
  ])
  func `the init document of every request follows the published schema`(
    arguments: [String],
  ) async throws {
    try place.folder.write(".git/HEAD", "x")

    let result = await place.run(arguments)

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `the document of a run that kept everything and found no version control follows it too`()
    async throws
  {
    _ = await place.run(["init", "--no-input"])

    let result = await place.run(["--json", "init"])

    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `the schema check fails an init document that breaks the schema`() async throws {
    let document = try await place.run(["--json", "init"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["gitignore"] = .string("maybe")
    members["hooks"] = .array([.string("pre-commit")])

    #expect(try !failures(of: .object(members)).isEmpty)
  }

  @Test
  func `a refusal to init is a document of the error schema`() async throws {
    let result = await place.run(["--json", "init", "--prefix", "Bad"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }
}
