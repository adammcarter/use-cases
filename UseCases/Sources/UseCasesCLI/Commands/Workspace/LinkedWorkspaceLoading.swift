import UseCasesCore

/// Loads a workspace and resolves its links, as every command that reads links does.
protocol LinkedWorkspaceLoading: Sendable {
  /// The workspace found from `start`, with its links.
  ///
  /// - Parameter start: Where to begin looking for the workspace.
  /// - Throws: ``LinkedWorkspaceError`` when the workspace is INVALID: it did not load, or its
  ///   links are a problem.
  func load(from start: WorkspaceStart) async throws(LinkedWorkspaceError)
    -> LinkedWorkspace
}
