import Foundation

/// Removes the sealed runs a later run has said everything again for, and that status does not
/// use for the workspace as it is now (chapter 12 §30, §31): `use-cases prune`, a person's
/// decision. Nothing else in the core ever deletes a run.
public protocol StorePruning: Sendable {
  /// The superseded runs of a workspace's store, worked out together from one read of it and the
  /// routes' fingerprints now, so that no run that supersedes another, and no run status uses, is
  /// planned away; and the leftovers of an interrupted prune. Reads only.
  ///
  /// - Parameters:
  ///   - workspace: A workspace that loaded.
  ///   - links: What link resolution found in it.
  /// - Throws: `StorePruningError` when the workspace is INVALID or the store cannot be read: a
  ///   damaged or unreadable run anywhere stops the plan, so a corrupt run is never touched.
  func plan(
    for workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(StorePruningError) -> PrunePlan

  /// Removes the planned runs, each whole: under its run lock, its folder is moved out of
  /// `runs/` in one step and then deleted. A run another process holds is left as it is.
  ///
  /// - Parameters:
  ///   - plan: What `plan(for:links:)` found.
  ///   - workspace: The workspace it was planned for.
  func remove(
    _ plan: PrunePlan,
    from workspace: LoadedWorkspace,
  ) -> PruneOutcome
}
