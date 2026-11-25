extension RunManifest {
  /// The manifest as `run.json` writes it (chapter 12 §11).
  var document: StoreJSONValue {
    .members([
      "run_version": .integer(1),
      "run_id": .string(identifier.text),
      "created_at": .string(createdAt),
      "kind": .string(kind.rawValue),
      "sources": .array(sources.map(\.document)),
      "errors": .strings(errors),
      "diagnostics": .array(diagnostics.map(\.document)),
      "unlinked_tests": .array(unlinkedTests.map(\.document)),
      "notes": .strings(notes),
    ])
  }
}
