/// A workspace as it is on disk now, with its links resolved.
public struct ResolvedWorkspace: Sendable {
  /// The workspace.
  public let workspace: LoadedWorkspace

  /// What link resolution found in it.
  public let links: LinkResolution

  /// Makes a resolved workspace.
  public init(
    workspace: LoadedWorkspace,
    links: LinkResolution,
  ) {
    self.workspace = workspace
    self.links = links
  }
}
