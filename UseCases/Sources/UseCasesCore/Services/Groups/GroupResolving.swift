/// Turns the groups a file defines into groups of use cases (chapter 03, chapter 09 §22).
protocol GroupResolving: Sendable {
  /// - Parameters:
  ///   - file: The groups file once it passed its schema.
  ///   - known: The use cases to resolve against. Without a safe set, only what the file says by
  ///     itself is checked.
  ///   - path: The groups file, which every problem names.
  /// - Returns: The groups, none of them when something is a problem, with every problem and
  ///   warning found.
  func resolve(
    _ file: GroupsFile,
    among known: KnownUseCases,
    in path: WorkspacePath,
  ) -> GroupsLoadResult
}
