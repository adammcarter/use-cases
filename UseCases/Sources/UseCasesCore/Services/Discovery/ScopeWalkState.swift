/// What the walk below the root has found so far.
struct ScopeWalkState {
  /// Child scopes whose `use-cases.yml` was read, with what it says.
  var settings: [WorkspacePath: ScopeSettings] = [:]

  /// Child scope folders whose `use-cases.yml` could not be used.
  var unreadable: Set<WorkspacePath> = []

  /// Folders whose `use-cases.yml` says `root: true`.
  var nestedWorkspaces: Set<WorkspacePath> = []

  var diagnostics: [Diagnostic] = []
}
