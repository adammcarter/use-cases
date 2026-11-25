/// Loads the optional root `use-case-groups.yml` as part of the model (chapter 09 §22). The
/// groups are resolved once, here, so that no later stage reopens the file.
protocol GroupsLoading: Sendable {
  /// - Parameters:
  ///   - root: The checked workspace root.
  ///   - scopes: Every scope of the workspace; a groups file in any but the root is a problem.
  ///   - known: The use cases to resolve the groups against.
  func load(
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
    among known: KnownUseCases,
  ) -> GroupsLoadResult
}
