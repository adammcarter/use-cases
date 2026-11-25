extension LoadedWorkspace {
  /// The same workspace holding these use cases instead, as the edits of a batch are followed
  /// one by one without loading it again.
  func holding(_ useCases: [LoadedUseCase]) -> LoadedWorkspace {
    LoadedWorkspace(
      root: root,
      scopes: scopes,
      useCases: useCases,
      warnings: warnings,
      bridge: bridge,
      groups: groups,
      rootFileWarnings: rootFileWarnings,
      heldProblems: heldProblems,
    )
  }
}
