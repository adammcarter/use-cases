import Foundation
import Testing
@testable import UseCasesCore

struct BundledSchemaLoaderTests {
  let loader = BundledSchemaLoader()

  @Test(arguments: AuthoredSchema.allCases)
  func `each bundled copy is byte for byte the published schema`(
    schema: AuthoredSchema,
  ) throws {
    let published = try Data(contentsOf: DocsSchemas.folder().appending(path: schema.fileName))

    #expect(try loader.schemaData(for: schema) == published)
  }

  @Test
  func `no schema is published that the build does not bundle`() throws {
    let published = try FileManager.default
      .contentsOfDirectory(atPath: DocsSchemas.folder().path)
      .filter {
        $0.hasSuffix(".schema.json")
      }
      .sorted()

    #expect(published == AuthoredSchema.allCases.map(\.fileName).sorted())
  }

  @Test(arguments: AuthoredSchema.allCases)
  func `each bundled schema compiles, so none uses a keyword the checker lacks`(
    schema: AuthoredSchema,
  ) throws {
    _ = try loader.loadChecker(for: schema)
  }

  @Test
  func `a bundle with no copy of a schema says which is missing`() throws {
    let empty = try #require(Bundle(path: FileManager.default.temporaryDirectory.path))
    let loader = BundledSchemaLoader(bundle: empty)

    #expect(throws: SchemaLoadingError.missing(.bridge)) {
      try loader.loadChecker(for: .bridge)
    }
  }

  @Test
  func `a copy that is not JSON is reported as such`() throws {
    try withBundle(holding: Data("{".utf8)) { bundle in
      let loader = BundledSchemaLoader(bundle: bundle)

      #expect(throws: SchemaLoadingError.invalidJSON(.workspace, .unexpectedEnd)) {
        try loader.loadChecker(for: .workspace)
      }
    }
  }

  @Test
  func `a copy that is JSON but not a schema is reported as such`() throws {
    try withBundle(holding: Data(#"{"maxProperties":1}"#.utf8)) { bundle in
      let loader = BundledSchemaLoader(bundle: bundle)
      let expected = SchemaLoadingError.invalidSchema(
        .workspace,
        .unknownKeyword("maxProperties", location: ""),
      )

      #expect(throws: expected) {
        try loader.loadChecker(for: .workspace)
      }
    }
  }

  @Test
  func `a copy that is not UTF-8 text is reported as unreadable`() throws {
    try withBundle(holding: Data([0xFF, 0xFE, 0x7B])) { bundle in
      let loader = BundledSchemaLoader(bundle: bundle)

      #expect(throws: SchemaLoadingError.unreadable(.workspace)) {
        try loader.loadChecker(for: .workspace)
      }
    }
  }

  /// Runs `body` with a bundle holding `contents` as the workspace schema, in the place a build
  /// keeps it, and removes the bundle afterwards.
  private func withBundle(
    holding contents: Data,
    _ body: (Bundle) throws -> Void,
  ) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: folder)
    }

    let schemas = folder.appending(path: "Schemas")
    try FileManager.default.createDirectory(
      at: schemas,
      withIntermediateDirectories: true,
    )
    try contents.write(to: schemas.appending(path: AuthoredSchema.workspace.fileName))

    try body(#require(Bundle(path: folder.path)))
  }
}
