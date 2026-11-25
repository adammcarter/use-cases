/// Loads a workspace the way every request does (chapter 09).
public protocol WorkspaceLoading: Sendable {
  /// The workspace found from `start`, or why it is not one.
  ///
  /// - Parameter start: Where to begin: a folder to search upward from, or the root itself.
  /// - Returns: The loaded workspace, when nothing makes it INVALID.
  /// - Throws: ``WorkspaceLoadingError``, with every independent problem that could safely be
  ///   found, sorted.
  func load(from start: WorkspaceStart) throws(WorkspaceLoadingError) -> LoadedWorkspace
}
