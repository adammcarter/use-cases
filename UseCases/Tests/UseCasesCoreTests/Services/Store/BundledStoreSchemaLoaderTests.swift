import Foundation
import Testing
@testable import UseCasesCore

struct BundledStoreSchemaLoaderTests {
  let loader = BundledStoreSchemaLoader()

  private var bundledFileNames: [String] {
    StoreSchema.allCases.map(\.fileName) + [StoreSchema.commonFileName]
  }

  @Test(arguments: StoreSchema.allCases.map(\.fileName) + [StoreSchema.commonFileName])
  func `each bundled copy is byte for byte the published schema`(fileName: String) throws {
    let published = try Data(contentsOf: DocsSchemas.storeFolder().appending(path: fileName))

    #expect(try loader.schemaData(named: fileName) == published)
  }

  @Test(arguments: StoreSchema.allCases)
  func `each bundled store schema compiles, so none uses a keyword the checker lacks`(
    schema: StoreSchema,
  ) throws {
    _ = try loader.loadChecker(for: schema)
  }

  @Test(arguments: StoreSchemaSamples.all)
  func `a store sample gets the verdict validate.py expects`(sample: StoreSchemaSample) throws {
    let checker = try loader.loadChecker(for: sample.schema)

    let failures = try checker.check(authored(sample.json))

    #expect(failures.isEmpty == sample.isValid, "\(failures.map(\.description))")
  }

  @Test(arguments: StoreSchemaSamples.all.filter { sample in
    sample.isValid
  })
  func `a checker that ignores unknown members still passes every valid sample`(
    sample: StoreSchemaSample,
  ) throws {
    let checker = try loader.loadChecker(
      for: sample.schema,
      unknownMembers: .ignore,
    )

    #expect(try checker.check(authored(sample.json)).isEmpty)
  }

  @Test(arguments: StoreSchemaSamples.all.filter { sample in
    !sample.isValid && !sample.name.contains("unknown member")
      && !sample.name.contains("report time") && !sample.name.contains("report start time")
  })
  func `a checker that ignores unknown members still refuses the other invalid samples`(
    sample: StoreSchemaSample,
  ) throws {
    let checker = try loader.loadChecker(
      for: sample.schema,
      unknownMembers: .ignore,
    )

    #expect(try !checker.check(authored(sample.json)).isEmpty)
  }

  @Test
  func `a bundle with no copy of a schema says which is missing`() throws {
    let empty = try #require(Bundle(path: FileManager.default.temporaryDirectory.path))
    let loader = BundledStoreSchemaLoader(bundle: empty)

    #expect(throws: StoreSchemaLoadingError.missing(StoreSchema.commonFileName)) {
      try loader.loadChecker(for: .run)
    }
  }

  @Test
  func `a copy that is not JSON is reported as such`() throws {
    try withBundle(
      common: Data("{".utf8),
      run: Data("{}".utf8),
    ) { bundle in
      let loader = BundledStoreSchemaLoader(bundle: bundle)

      #expect(
        throws: StoreSchemaLoadingError.invalidJSON(
          StoreSchema.commonFileName,
          .unexpectedEnd,
        ),
      ) {
        try loader.loadChecker(for: .run)
      }
    }
  }

  @Test
  func `a copy that is JSON but not a schema is reported as such`() throws {
    try withBundle(
      common: Data("{}".utf8),
      run: Data(#"{"maxProperties":1}"#.utf8),
    ) { bundle in
      let loader = BundledStoreSchemaLoader(bundle: bundle)

      #expect(
        throws: StoreSchemaLoadingError.invalidSchema(
          StoreSchema.run.fileName,
          .unknownKeyword("maxProperties", location: ""),
        ),
      ) {
        try loader.loadChecker(for: .run)
      }
    }
  }

  @Test
  func `a copy that is not UTF-8 text is reported as unreadable`() throws {
    try withBundle(
      common: Data("{}".utf8),
      run: Data([0xFF, 0xFE, 0x7B]),
    ) { bundle in
      let loader = BundledStoreSchemaLoader(bundle: bundle)

      #expect(throws: StoreSchemaLoadingError.unreadable(StoreSchema.run.fileName)) {
        try loader.loadChecker(for: .run)
      }
    }
  }

  /// Runs `body` with a bundle holding these as the common and run schemas, in the place a build
  /// keeps them, and removes the bundle afterwards.
  private func withBundle(
    common: Data,
    run: Data,
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
    try common.write(to: schemas.appending(path: StoreSchema.commonFileName))
    try run.write(to: schemas.appending(path: StoreSchema.run.fileName))

    try body(#require(Bundle(path: folder.path)))
  }
}
