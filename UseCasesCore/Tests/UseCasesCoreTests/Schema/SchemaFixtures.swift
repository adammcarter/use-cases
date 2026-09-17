import Foundation
import Testing
@testable import UseCasesCore

/// One diagnostic inside a golden case.
struct GoldenDiagnostic: Decodable {
  let code: String
  let severity: String
  let message: String
  let sourcePath: String?
  let jsonPointer: String?
  let entityIdentifier: String?
  let relatedIdentifiers: [String]

  enum CodingKeys: String, CodingKey {
    case code
    case severity
    case message
    case sourcePath = "source_path"
    case jsonPointer = "json_pointer"
    case entityIdentifier = "entity_id"
    case relatedIdentifiers = "related_ids"
  }
}

/// One golden case captured from the TypeScript validator.
struct SchemaGoldenCase: Decodable {
  let name: String
  let schemaFile: String
  let document: String
  let sourcePath: String?
  let isValid: Bool
  let diagnostics: [GoldenDiagnostic]

  enum CodingKeys: String, CodingKey {
    case name
    case schemaFile = "schema_file"
    case document
    case sourcePath = "source_path"
    case isValid = "ok"
    case diagnostics
  }
}

/// The real repository files the schema tests run against.
///
/// Schemas and fixture workspaces are read from the checkout rather than copied,
/// so a schema edit cannot silently drift away from what the tests pin.
enum SchemaFixtures {
  /// The repository root, derived from this file's own location.
  static var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // Schema
      .deletingLastPathComponent() // UseCasesCoreTests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // UseCasesCore
      .deletingLastPathComponent() // <repository root>
  }

  /// `schemas/v1`, the 27 frozen schema files.
  static var schemasDirectory: URL {
    repositoryRoot.appendingPathComponent("schemas/v1", isDirectory: true)
  }

  /// The bundled fixture workspaces the TypeScript suite validates.
  static func fixtureWorkspace(_ name: String) -> URL {
    repositoryRoot.appendingPathComponent("tests/fixtures/workspaces/\(name)", isDirectory: true)
  }

  /// A registry over the checked-in schemas.
  static func registry() throws -> SchemaRegistry {
    try SchemaRegistry(schemasDirectory: schemasDirectory)
  }

  /// Every golden case, decoded from the generated corpus.
  static func goldenCases() throws -> [SchemaGoldenCase] {
    let decoder = JSONDecoder()
    let data = try #require(SchemaGoldenCorpus.json.data(using: .utf8))
    return try decoder.decode([SchemaGoldenCase].self, from: data)
  }

  /// The single golden case with `name`.
  static func goldenCase(named name: String) throws -> SchemaGoldenCase {
    let match = try goldenCases().first { candidate in
      candidate.name == name
    }
    return try #require(match)
  }
}
