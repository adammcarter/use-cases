import Foundation

/// Where a workspace load begins (chapter 16 §3).
public enum WorkspaceStart: Equatable, Sendable {
  /// Walk up from this folder to the nearest `use-cases.yml` that says `root: true`.
  case searchingUpward(from: URL)

  /// This folder is the root itself, as `--workspace DIR` names it. A folder whose
  /// `use-cases.yml` is a child scope's is refused.
  case workspace(URL)
}
