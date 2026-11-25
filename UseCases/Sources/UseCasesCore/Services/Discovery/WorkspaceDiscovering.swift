/// Finds the scopes of a workspace and the definition files each owns (chapter 04, chapter 09
/// §6, §11).
protocol WorkspaceDiscovering: Sendable {
  /// Walks the workspace below its root, never entering an excluded folder, a nested
  /// workspace or a symlink, and reports every problem it can find along the way.
  func discover(root: WorkspaceRoot) -> WorkspaceDiscovery
}
