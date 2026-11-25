/// A workspace as a plan would leave it, read the way every command reads one: the loader and the
/// link resolver that see the real files with the plan's contents laid over them.
public struct WorkspaceView: Sendable {
  /// Loads the workspace as the plan would leave it.
  public let loader: any WorkspaceLoading

  /// Resolves its links, reading the same view.
  public let resolver: any LinkResolving
}
