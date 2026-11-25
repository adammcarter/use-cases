public extension WorkspaceStatus {
  /// The same workspace seen through some of its use cases, such as the members of a group: the
  /// gate of the result holds those use cases only (chapter 16 §10).
  func limited(to identifiers: Set<String>) -> WorkspaceStatus {
    WorkspaceStatus(
      useCases: useCases.filter { useCase in
        identifiers.contains(useCase.identifier)
      },
      warnings: warnings,
      hasSealedRuns: hasSealedRuns,
      signOffRequired: signOffRequired,
      hasRunCommand: hasRunCommand,
      store: store,
      runIdentifiers: runIdentifiers,
    )
  }
}
