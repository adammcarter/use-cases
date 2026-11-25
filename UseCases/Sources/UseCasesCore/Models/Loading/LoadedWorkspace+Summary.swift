public extension LoadedWorkspace {
  /// The counts `validate` reports: use cases by authored state, and the definition files read.
  var summary: WorkspaceSummary {
    let draft = useCases.count { useCase in
      if case .draft = useCase.definition.authoredState {
        return true
      }

      return false
    }

    return WorkspaceSummary(
      useCases: useCases.count,
      ready: useCases.count - draft,
      draft: draft,
      files: scopes.flatMap(\.discovered.definitionFiles).sorted().map(\.text),
    )
  }
}
