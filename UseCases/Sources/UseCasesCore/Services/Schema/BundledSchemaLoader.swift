import Foundation

/// Loads the copies of the four schemas that ship inside the build.
struct BundledSchemaLoader: SchemaLoading {
  private let bundle: Bundle
  private let reader: any JSONReading

  init(
    bundle: Bundle = .module,
    reader: any JSONReading = JSONReader(),
  ) {
    self.bundle = bundle
    self.reader = reader
  }

  func loadChecker(for schema: AuthoredSchema) throws(SchemaLoadingError) -> any SchemaChecking {
    let text = try schemaText(for: schema)

    let value: AuthoredValue
    do {
      value = try reader.read(text)
    } catch {
      throw .invalidJSON(schema, error)
    }

    do {
      return try SchemaChecker(schema: value)
    } catch {
      throw .invalidSchema(schema, error)
    }
  }

  /// The bytes of the bundled copy, exactly as shipped.
  func schemaData(for schema: AuthoredSchema) throws(SchemaLoadingError) -> Data {
    guard
      let url = bundle.url(
        forResource: "\(schema.rawValue).schema",
        withExtension: "json",
        subdirectory: "Schemas",
      ),
      let data = try? Data(contentsOf: url)
    else {
      throw .missing(schema)
    }

    return data
  }

  private func schemaText(for schema: AuthoredSchema) throws(SchemaLoadingError) -> String {
    let data = try schemaData(for: schema)
    guard let text = String(data: data, encoding: .utf8) else {
      throw .unreadable(schema)
    }

    return text
  }
}
