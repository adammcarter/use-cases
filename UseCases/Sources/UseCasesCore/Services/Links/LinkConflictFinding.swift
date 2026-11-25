/// Finds the links that cannot all stand: a binding with two sources, two links with one key, and
/// links of one use case and role that overlap (chapter 08 "Rules for every link").
protocol LinkConflictFinding: Sendable {
  /// The conflicts among `links`. A binding claimed by two sources and two links with one key
  /// are problems; overlapping links of one use case and role are warnings.
  ///
  /// - Parameter definitions: The definition file of each use case, where a conflict over one of
  ///   its bindings is filed.
  func conflicts(
    among links: [ResolvedLink],
    definitions: [UseCaseIdentifier: WorkspacePath],
  ) -> [Diagnostic]
}
