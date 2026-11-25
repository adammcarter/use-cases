import Foundation
import MCP

/// The output schemas that ship inside the build: copies of `docs/schemas/output` and the
/// schemas they refer to, which a test holds byte for byte to the design.
struct BundledOutputSchemas: OutputSchemaLoading {
  private let bundle: Bundle
  private let reader: any JSONValueReading

  init(
    bundle: Bundle = .module,
    reader: any JSONValueReading = JSONValueReader(),
  ) {
    self.bundle = bundle
    self.reader = reader
  }

  func outputSchema(file: String) throws(OutputSchemaError) -> Value {
    var documents: [String: Value] = [:]

    for name in files() {
      documents[name] = try document(named: name)
    }

    guard documents[file] != nil else {
      throw .missing(file: file)
    }

    do {
      return try SchemaInliner(documents: documents).inlined(file)
    } catch {
      throw .notStandalone(
        file: file,
        reason: error,
      )
    }
  }

  /// The names of the bundled copies.
  func files() -> [String] {
    // On Linux the bundle lists these as `NSURL`s, whose last component is optional.
    (bundle.urls(
      forResourcesWithExtension: "json",
      subdirectory: "Schemas",
    ) ?? []).compactMap(\.lastPathComponent).sorted()
  }

  /// The bytes of one bundled copy, exactly as shipped.
  func data(named name: String) throws(OutputSchemaError) -> Data {
    guard
      let url = bundle.url(
        forResource: name,
        withExtension: nil,
        subdirectory: "Schemas",
      ),
      let data = try? Data(contentsOf: url)
    else {
      throw .missing(file: name)
    }

    return data
  }

  private func document(named name: String) throws(OutputSchemaError) -> Value {
    guard
      let text = try String(
        data: data(named: name),
        encoding: .utf8,
      ),
      let value = reader.value(of: text)
    else {
      throw .unreadable(file: name)
    }

    return value
  }
}
