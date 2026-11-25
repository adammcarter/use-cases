/// What discovery found: the scopes with their definition files, and every problem met on the
/// way (chapter 09 §6, §11, §27).
struct WorkspaceDiscovery: Equatable, Sendable {
  /// The scopes whose `use-cases.yml` could be read. When `diagnostics` holds an error the
  /// workspace is INVALID and this tree is for reporting only (chapter 09 §26).
  let scopeTree: ScopeTree

  /// Folders below the root whose `use-cases.yml` says `root: true`: separate workspaces, never
  /// entered (chapter 04), sorted by path.
  let nestedWorkspaces: [WorkspacePath]

  /// Scope folders whose `use-cases.yml` could not be read, sorted by path. Each has a
  /// diagnostic; none is in the tree.
  let unreadableScopes: [WorkspacePath]

  /// Every problem found, sorted by file, position and code (chapter 09 §27.1).
  let diagnostics: [Diagnostic]

  /// Whether discovery found nothing that makes the workspace INVALID.
  var isValid: Bool {
    !diagnostics.contains { diagnostic in
      diagnostic.severity == .error
    }
  }
}
