/// The scopes of a workspace: the root first, then every other scope sorted by path bytes, so
/// the tree is the same however the file system listed its folders (chapter 09 §6.1).
struct ScopeTree: Equatable, Sendable {
  let root: DiscoveredScope

  /// Every scope below the root, sorted by directory.
  let descendants: [DiscoveredScope]

  init(
    root: DiscoveredScope,
    descendants: [DiscoveredScope],
  ) {
    self.root = root
    self.descendants = descendants.sorted { lhs, rhs in
      lhs.directory < rhs.directory
    }
  }

  /// All scopes, the root first.
  var scopes: [DiscoveredScope] {
    [root] + descendants
  }

  /// The scope in this folder, if there is one.
  func scope(at directory: WorkspacePath) -> DiscoveredScope? {
    scopes.first { scope in
      scope.directory == directory
    }
  }

  /// The scopes whose parent is this folder's scope, sorted by directory.
  func children(of directory: WorkspacePath) -> [DiscoveredScope] {
    descendants.filter { scope in
      scope.parent == directory
    }
  }
}
