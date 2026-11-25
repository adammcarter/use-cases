import Foundation

/// Plans the hooks of a clone from what is in its hooks folder (chapter 18 §3, §4): a hook is
/// added only where there is none, removed only when it is exactly the one Use Cases wrote, and
/// anything else is left alone and reported.
public struct HookPlanner: HookPlanning {
  let git: any GitInspecting
  let fileSystem: any FileSystemReading

  /// Makes the planner that reads the real file system.
  ///
  /// - Parameter git: Finds the clone's hooks folder.
  public init(git: any GitInspecting) {
    self.init(
      git: git,
      fileSystem: LocalFileSystem(),
    )
  }

  init(
    git: any GitInspecting,
    fileSystem: any FileSystemReading,
  ) {
    self.git = git
    self.fileSystem = fileSystem
  }

  public func plan(_ request: HooksRequest) async throws(HooksError) -> HooksPlan {
    let root = fileSystem.canonicalLocation(of: request.root)
    let location = try await git.locate(from: root)
    let workspace = root.relativePath(from: location.workTree)

    var outcome = Outcome()

    for hook in HookName.allCases {
      let script = HookScript(
        hook: hook,
        workspace: workspace,
      )
      let state = try state(
        of: script,
        in: location,
      )

      try change(
        script,
        state: state,
        request: request,
        location: location,
        outcome: &outcome,
      )
    }

    return HooksPlan(
      hooksFolder: location.hooksFolder.relativePath(from: root),
      isManaged: location.isManaged,
      hooks: outcome.hooks,
      changed: outcome.changed,
      notes: outcome.notes,
      needsAttention: outcome.needsAttention,
      writes: FolderWrite(
        folder: location.hooksFolder.deletingLastPathComponent(),
        plan: WritePlan(changes: outcome.changes),
      ),
    )
  }
}
