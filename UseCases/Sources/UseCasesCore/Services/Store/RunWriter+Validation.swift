import Foundation

extension RunWriter {
  /// Reads the bytes of a file as JSON and checks them against a schema. A document that breaks
  /// it is a bug of the writer, so nothing is written and the error says what was wrong.
  func validated(
    _ bytes: [UInt8],
    against checker: any SchemaChecking,
    location: String,
  ) throws(StoreWritingError) -> AuthoredValue {
    guard let text = String(
      bytes: bytes,
      encoding: .utf8,
    ) else {
      throw .invalidDocument(
        location: location,
        problems: "it is not UTF-8 text",
      )
    }

    let value: AuthoredValue
    do {
      value = try json.read(text)
    } catch {
      throw .invalidDocument(
        location: location,
        problems: "it is not JSON: \(error)",
      )
    }

    let failures = checker.check(value)
    guard failures.isEmpty else {
      throw .invalidDocument(
        location: location,
        problems: failures.prefix(3).map(\.description).joined(separator: "; "),
      )
    }

    return value
  }

  /// Reads a document that passed its schema into a model.
  func decoded<Value>(
    _ location: String,
    _ read: () throws(AuthoredShapeError) -> Value,
  ) throws(StoreWritingError) -> Value {
    do {
      return try read()
    } catch {
      throw .invalidDocument(
        location: location,
        problems: error.description,
      )
    }
  }

  /// Refuses a run that already has its completion marker.
  func requireUnsealed(
    _ run: RunIdentifier,
    in workspace: URL,
  ) throws(StoreWritingError) {
    let marker = folder(
      of: run,
      in: workspace,
    ).appending(StoreLayout.completionFile)

    let kind = try reading { () throws(StoreProblem) in
      try access.kind(of: marker)
    }
    guard kind == nil else {
      throw .sealed(run)
    }
  }
}
