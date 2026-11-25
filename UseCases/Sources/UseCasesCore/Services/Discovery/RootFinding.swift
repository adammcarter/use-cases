import Foundation

/// Names the workspace root for a caller that is not in the root already (chapter 16 §3).
/// The core's loader never searches upward (chapter 09 §3); callers use this first.
protocol RootFinding: Sendable {
  /// Walks up from `start` to the nearest folder whose `use-cases.yml` says `root: true`,
  /// passing over child scopes. A nested workspace is found first from inside it.
  func findRoot(from start: URL) throws(RootFindingError) -> WorkspaceRoot

  /// Checks that this folder is itself the root, as `--workspace DIR` requires: a folder whose
  /// `use-cases.yml` lacks `root: true` is a child scope and is refused.
  func requireRoot(at folder: URL) throws(RootFindingError) -> WorkspaceRoot
}
