import Foundation

/// A workspace root that has been checked: a folder whose `use-cases.yml` says `root: true`.
struct WorkspaceRoot: Equatable, Sendable {
  /// The canonical absolute folder (chapter 09 §4).
  let directory: URL

  /// What the root's `use-cases.yml` says.
  let settings: ScopeSettings
}
