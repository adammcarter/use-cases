import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The 27 frozen schema files travel INSIDE the binary (ADR 0007 decision 3:
/// one downloadable binary per platform). A shipped binary runs inside a user's
/// own project, where walking up the filesystem finds nothing — so the embedded
/// copy is the only one it has, and these tests are what stops it rotting.
struct EmbeddedSchemasTests {
  /// Read a schema file from the checkout, which is the oracle the embedded
  /// copy is compared against.
  private func fileOnDisk(_ fileName: String) throws -> String {
    try String(
      contentsOf: SchemaFixtures.schemasDirectory.appendingPathComponent(fileName),
      encoding: .utf8,
    )
  }

  @Test(arguments: SchemaRegistry.schemaFileNames)
  func `an embedded schema is the exact bytes of its file on disk`(fileName: String) throws {
    let embedded = try #require(EmbeddedSchemas.byFileName[fileName])

    try #expect(embedded == fileOnDisk(fileName))
  }

  @Test
  func `the embedded set is exactly the twenty seven published files`() {
    #expect(EmbeddedSchemas.byFileName.count == 27)
    #expect(Set(EmbeddedSchemas.byFileName.keys) == Set(SchemaRegistry.schemaFileNames))
  }

  @Test
  func `no embedded schema is empty`() {
    #expect(EmbeddedSchemas.byFileName.values.allSatisfy { !$0.isEmpty })
  }

  @Test
  func `the embedded registry carries the same schemas as the one read from disk`() throws {
    let embedded = try SchemaRegistry()
    let fromDisk = try SchemaFixtures.registry()

    for identifier in SchemaRegistry.publicSchemaIdentifiers {
      let embeddedSchema = try #require(embedded.schema(withIdentifier: identifier))
      let diskSchema = try #require(fromDisk.schema(withIdentifier: identifier))
      #expect(embeddedSchema == diskSchema)
    }
  }

  @Test
  func `the embedded registry lists every published schema in the frozen order`() throws {
    let listed = try SchemaRegistry().publicSchemas()

    #expect(listed.map(\.identifier) == SchemaRegistry.publicSchemaIdentifiers)
    #expect(listed.allSatisfy { $0.schema != nil })
  }

  @Test
  func `a document validates from a directory with no schemas above it`() throws {
    let temporary = try TemporaryDirectory()
    let workspace = try temporary.makeDirectory("someone-elses-project/src")

    // The proof that nothing above this directory could have been walked up to.
    #expect(throws: SchemaError.self) {
      try SchemaRegistry.locateSchemasDirectory(startingAt: workspace)
    }

    let result = try SchemaRegistry().validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: "common.schema.json"),
      value: .object(JSONObject([("schema_version", .number(1))])),
      sourcePath: nil,
    )

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `an invalid document is still refused with no schemas above it`() throws {
    let temporary = try TemporaryDirectory()

    #expect(throws: SchemaError.self) {
      try SchemaRegistry.locateSchemasDirectory(startingAt: temporary.url)
    }

    let result = try SchemaRegistry().validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: "common.schema.json"),
      value: .object(JSONObject([("schema_version", .number(2))])),
      sourcePath: "doc.json",
    )

    #expect(result.isValid == false)
    #expect(result.diagnostics.isEmpty == false)
  }

  @Test
  func `the running binary has no schemas directory above it and needs none`() throws {
    let executable = try #require(CommandLine.arguments.first)
    let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent()

    // This is the shipped-binary case: the executable sits outside any checkout.
    #expect(throws: SchemaError.self) {
      try SchemaRegistry.locateSchemasDirectory(startingAt: executableDirectory)
    }

    let registry = try SchemaRegistry()

    #expect(registry.publicSchemas().count == 27)
  }
}
