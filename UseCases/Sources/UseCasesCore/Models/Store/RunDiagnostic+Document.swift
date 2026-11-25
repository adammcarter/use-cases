extension RunDiagnostic {
  /// The diagnostic as `run.json` writes it. A field it does not have is left out.
  var document: StoreJSONValue {
    .present([
      "problem": .string(problem),
      "use_case": useCase.map(\.text).map(StoreJSONValue.string),
      "route": route.map(\.text).map(StoreJSONValue.string),
      "fingerprint": fingerprint.map(\.text).map(StoreJSONValue.string),
      "files": files.isEmpty ? nil : .strings(files.map(\.text)),
      "links": links.isEmpty ? nil : .strings(links),
    ])
  }
}
