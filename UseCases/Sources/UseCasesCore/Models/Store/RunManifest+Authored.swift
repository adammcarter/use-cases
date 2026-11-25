extension RunManifest {
  /// Reads a manifest of version 1, after it passed the run schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var sources: [RunSource] = []
    for source in try object.objects("sources") {
      try sources.append(RunSource(authored: source))
    }

    var diagnostics: [RunDiagnostic] = []
    for diagnostic in try object.objects("diagnostics") {
      try diagnostics.append(RunDiagnostic(authored: diagnostic))
    }

    var unlinkedTests: [UnlinkedTest] = []
    for test in try object.objects("unlinked_tests") {
      try unlinkedTests.append(UnlinkedTest(authored: test))
    }

    try self.init(
      identifier: object.requiredRunIdentifier("run_id"),
      createdAt: object.requiredString("created_at"),
      kind: object.requiredChoice(
        "kind",
        as: RunKind.self,
      ),
      sources: sources,
      errors: object.strings("errors"),
      diagnostics: diagnostics,
      unlinkedTests: unlinkedTests,
      notes: object.strings("notes"),
    )
  }
}
