import Foundation
import Testing
@testable import UseCasesCore

/// The three INTERNAL marker validator schemas travel inside the binary beside
/// the 27 published ones, and must never leak into the published catalogue:
/// `schema list` and its 27 ids are frozen contract (ADR 0007 decision 8).
///
/// Their source is `schemas/markers`, a sibling of the published `schemas/v1`
/// that nothing scanning the catalogue reads. They lived under
/// `packages/core/src/markers/schemas` until ADR 0007 row 10d deleted the
/// TypeScript; the files moved rather than went, because this drift test is the
/// only thing stopping the embedded copies and the committed ones parting.
struct EmbeddedMarkerSchemasTests {
  static let fileNames = [
    "binding-registry-event.schema.json",
    "freshness-status.schema.json",
    "proof-event.schema.json",
  ]

  private static var markerSchemasDirectory: URL {
    SchemaFixtures.repositoryRoot
      .appendingPathComponent("schemas/markers", isDirectory: true)
  }

  @Test(arguments: fileNames)
  func `an embedded marker schema is the exact bytes of its file on disk`(fileName: String) throws {
    let embedded = try #require(EmbeddedMarkerSchemas.byFileName[fileName])
    let onDisk = try String(
      contentsOf: Self.markerSchemasDirectory.appendingPathComponent(fileName),
      encoding: .utf8,
    )

    #expect(embedded == onDisk)
  }

  @Test
  func `the embedded marker set is exactly the three files on disk`() throws {
    let onDisk = try FileManager.default
      .contentsOfDirectory(atPath: Self.markerSchemasDirectory.path)
      .filter { name in
        name.hasSuffix(".schema.json")
      }

    #expect(Set(EmbeddedMarkerSchemas.byFileName.keys) == Set(onDisk))
    #expect(Set(EmbeddedMarkerSchemas.byFileName.keys) == Set(Self.fileNames))
  }

  @Test
  func `no marker schema joins the published catalogue`() throws {
    let markerIdentifiers = Set([
      MarkerConstants.bindingRegistrySchemaIdentifier,
      MarkerConstants.evidenceSchemaIdentifier,
      MarkerConstants.statusSchemaIdentifier,
    ])
    let registry = try SchemaRegistry()

    #expect(SchemaRegistry.publicSchemaIdentifiers.count == 27)
    #expect(registry.publicSchemas().count == 27)
    #expect(markerIdentifiers.isDisjoint(with: SchemaRegistry.publicSchemaIdentifiers))
    #expect(markerIdentifiers.isDisjoint(with: registry.publicSchemas().map(\.identifier)))
    for identifier in markerIdentifiers {
      #expect(registry.schema(withIdentifier: identifier) == nil)
    }
  }

  @Test(arguments: fileNames)
  func `every marker schema compiles under the strict keyword set`(fileName: String) throws {
    let text = try #require(EmbeddedMarkerSchemas.byFileName[fileName])
    let schema = try JSONParser.parse(text)
    let validator = try SchemaValidator(registry: SchemaRegistry())

    #expect(validator.compilationProblem(in: schema, root: schema) == nil)
  }
}
