extension UnlinkedTest {
  /// The test as `run.json` writes it. A test with no place says so with `null`.
  var document: StoreJSONValue {
    .members([
      "test": .string(test),
      "file": file.map(StoreJSONValue.string) ?? .null,
      "line": line.map(StoreJSONValue.integer) ?? .null,
      "status": .string(status.rawValue),
    ])
  }
}
