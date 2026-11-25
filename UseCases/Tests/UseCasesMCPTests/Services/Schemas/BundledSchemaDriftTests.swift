import Foundation
import Testing
@testable import UseCasesMCP

/// The copies of the schemas that ship in the build are the design's, byte for byte.
struct BundledSchemaDriftTests {
  private let schemas = BundledOutputSchemas()

  /// The folders of the design a published schema lives in.
  private static let folders = [
    "schemas/authored", "schemas/engine", "schemas/output",
  ]

  private func published(_ name: String) throws -> Data {
    let docs = try DocsFolder.url()

    for folder in Self.folders {
      let file = docs.appending(path: "\(folder)/\(name)")

      if let data = try? Data(contentsOf: file) {
        return data
      }
    }

    throw Missing(name: name)
  }

  private struct Missing: Error {
    let name: String
  }

  /// Every schema the build ships, named here so that a copy added or dropped is seen.
  static let shipped = [
    "cli-apply.schema.json", "cli-approve.schema.json", "cli-common.schema.json",
    "cli-docs.schema.json", "cli-error.schema.json", "cli-links.schema.json",
    "cli-record.schema.json", "cli-remove.schema.json", "cli-render.schema.json",
    "cli-save.schema.json", "cli-search.schema.json", "cli-show.schema.json",
    "cli-status.schema.json", "cli-validate.schema.json", "cli-verify.schema.json",
    "common.schema.json", "result.schema.json", "run.schema.json",
    "transformer-results-request.schema.json", "use-cases.schema.json",
  ]

  @Test(arguments: shipped)
  func `a bundled schema is the published one, byte for byte`(name: String) throws {
    #expect(try schemas.data(named: name) == published(name))
  }

  @Test
  func `every tool's schema is bundled, with each schema it refers to`() {
    let files = Set(schemas.files())

    for tool in ToolDefinition.all {
      #expect(files.contains(tool.outputSchemaFile))
    }

    #expect(files.isSuperset(of: [
      "cli-common.schema.json", "common.schema.json", "run.schema.json", "result.schema.json",
      "transformer-results-request.schema.json", "use-cases.schema.json",
    ]))
  }

  @Test
  func `no schema is bundled that nothing uses`() {
    let used = Set(ToolDefinition.all.map(\.outputSchemaFile)).union([
      "cli-error.schema.json", "cli-common.schema.json", "common.schema.json",
      "run.schema.json", "result.schema.json", "transformer-results-request.schema.json",
      "use-cases.schema.json",
    ])

    #expect(Set(schemas.files()) == used)
  }
}
