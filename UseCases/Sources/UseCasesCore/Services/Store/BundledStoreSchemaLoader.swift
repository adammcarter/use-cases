import Foundation

/// Loads the copies of the store schemas that ship inside the build.
struct BundledStoreSchemaLoader: StoreSchemaLoading {
  private let bundle: Bundle
  private let reader: any JSONReading

  init(
    bundle: Bundle = .module,
    reader: any JSONReading = JSONReader(),
  ) {
    self.bundle = bundle
    self.reader = reader
  }

  func loadChecker(
    for schema: StoreSchema,
    unknownMembers: UnknownMembers,
  ) throws(StoreSchemaLoadingError) -> any SchemaChecking {
    let common = try document(named: StoreSchema.commonFileName)
    let value = try document(named: schema.fileName)

    do {
      return try SchemaChecker(
        schema: value,
        documents: [StoreSchema.commonFileName: common],
        unknownMembers: unknownMembers,
      )
    } catch {
      throw .invalidSchema(schema.fileName, error)
    }
  }

  /// The bytes of the bundled copy of a schema file, exactly as shipped.
  func schemaData(named fileName: String) throws(StoreSchemaLoadingError) -> Data {
    let name = fileName.replacingOccurrences(of: ".json", with: "")
    guard
      let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Schemas",
      ),
      let data = try? Data(contentsOf: url)
    else {
      throw .missing(fileName)
    }

    return data
  }

  private func document(named fileName: String) throws(StoreSchemaLoadingError) -> AuthoredValue {
    let data = try schemaData(named: fileName)
    guard let text = String(data: data, encoding: .utf8) else {
      throw .unreadable(fileName)
    }

    do {
      return try reader.read(text)
    } catch {
      throw .invalidJSON(fileName, error)
    }
  }
}
