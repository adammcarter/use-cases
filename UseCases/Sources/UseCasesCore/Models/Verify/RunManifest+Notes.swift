extension RunManifest {
  /// The same manifest with one more note.
  func adding(note: String) -> RunManifest {
    RunManifest(
      identifier: identifier,
      createdAt: createdAt,
      kind: kind,
      sources: sources,
      errors: errors,
      diagnostics: diagnostics,
      unlinkedTests: unlinkedTests,
      notes: notes + [note],
    )
  }
}
