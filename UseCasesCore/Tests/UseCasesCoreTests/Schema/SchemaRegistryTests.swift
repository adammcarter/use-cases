import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The registry is the catalogue of the 28 published schemas. Their ids, their
/// order and the fact that every one of them loads are frozen contract (ADR 0007
/// decision 8): the MCP server lists them and the CLI validates against them.
struct SchemaRegistryTests {
  @Test
  func `there are twenty eight public schema ids`() {
    #expect(SchemaRegistry.publicSchemaIdentifiers.count == 28)
  }

  @Test
  func `the ids keep their frozen order`() {
    let identifiers = SchemaRegistry.publicSchemaIdentifiers

    #expect(identifiers.first == "https://use-cases.dev/schemas/v1/common.schema.json")
    #expect(identifiers[1] == "https://use-cases.dev/schemas/v1/cli-result.schema.json")
    #expect(identifiers[2] == "https://use-cases.dev/schemas/v1/use-case-file.schema.json")
    #expect(identifiers.last == "https://use-cases.dev/schemas/v1/mcp-tool-results.schema.json")
  }

  @Test
  func `no id is listed twice`() {
    #expect(Set(SchemaRegistry.publicSchemaIdentifiers).count == 28)
  }

  @Test
  func `an id is the versioned url of its file name`() {
    #expect(
      SchemaRegistry.schemaIdentifier(forFileName: "marker.schema.json")
        == "https://use-cases.dev/schemas/v1/marker.schema.json",
    )
  }

  @Test
  func `every public id loads a schema carrying that id`() throws {
    let registry = try SchemaFixtures.registry()

    for identifier in SchemaRegistry.publicSchemaIdentifiers {
      let schema = try #require(registry.schema(withIdentifier: identifier))
      #expect(schema["$id"] == .string(identifier))
    }
  }

  @Test
  func `an unknown id loads nothing`() throws {
    let registry = try SchemaFixtures.registry()

    #expect(registry.schema(withIdentifier: "https://use-cases.dev/schemas/v1/nope.json") == nil)
  }

  @Test
  func `the public schemas are listed in the frozen order`() throws {
    let registry = try SchemaFixtures.registry()
    let listed = registry.publicSchemas()

    #expect(listed.map(\.identifier) == SchemaRegistry.publicSchemaIdentifiers)
    #expect(listed.allSatisfy { $0.schema != nil })
  }

  @Test
  func `the published schemas all compile`() {
    let result = SchemaRegistry.validatePublicSchemas(
      schemasDirectory: SchemaFixtures.schemasDirectory,
    )

    #expect(result.isValid)
    #expect(result.schemaCount == 28)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `a missing schemas directory fails to compile with a stable code`() throws {
    let temporary = try TemporaryDirectory()
    let result = SchemaRegistry.validatePublicSchemas(
      schemasDirectory: temporary.url.appendingPathComponent("absent", isDirectory: true),
    )

    #expect(result.isValid == false)
    #expect(result.schemaCount == 0)
    #expect(result.diagnostics.map(\.code) == ["schema.compile_failed"])
  }

  @Test
  func `loading from a directory without the schemas throws`() throws {
    let temporary = try TemporaryDirectory()

    #expect(throws: SchemaError.self) {
      try SchemaRegistry(schemasDirectory: temporary.url)
    }
  }

  @Test
  func `validating against an unknown id reports it against the source path`() throws {
    let registry = try SchemaFixtures.registry()
    let identifier = SchemaRegistry.schemaIdentifier(forFileName: "does-not-exist.schema.json")

    let result = registry.validate(
      schemaIdentifier: identifier,
      value: .object(JSONObject()),
      sourcePath: "z.json",
    )
    let diagnostic = try #require(result.diagnostics.first)

    #expect(result.isValid == false)
    #expect(result.diagnostics.count == 1)
    #expect(diagnostic.code == "schema.unknown")
    #expect(diagnostic.message == "Unknown schema: \(identifier)")
    #expect(diagnostic.sourcePath == "z.json")
    #expect(diagnostic.entityIdentifier == nil)
  }

  @Test
  func `a valid document reports no diagnostics`() throws {
    let registry = try SchemaFixtures.registry()

    let result = registry.validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: "common.schema.json"),
      value: .object(JSONObject([("schema_version", .number(1))])),
      sourcePath: nil,
    )

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `the schemas directory is found by walking up from a nested path`() throws {
    let temporary = try TemporaryDirectory()
    try temporary.writeFile("schemas/v1/common.schema.json", contents: "{}")
    let nested = try temporary.makeDirectory("a/b/c")

    let located = try SchemaRegistry.locateSchemasDirectory(startingAt: nested)

    #expect(
      located.resolvingSymlinksInPath().path
        == temporary.url.appendingPathComponent("schemas/v1").resolvingSymlinksInPath().path,
    )
  }

  @Test
  func `a tree without schemas has no schemas directory to find`() throws {
    let temporary = try TemporaryDirectory()
    let nested = try temporary.makeDirectory("a/b")

    #expect(throws: SchemaError.self) {
      try SchemaRegistry.locateSchemasDirectory(startingAt: nested)
    }
  }
}
