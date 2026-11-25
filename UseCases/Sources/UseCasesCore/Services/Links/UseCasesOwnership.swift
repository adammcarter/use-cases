/// Which files and folders belong to Use Cases itself, so the scan leaves them alone (chapter 09
/// §20.3): every scope's `use-cases.yml`, every discovered definition file, the root's groups and
/// bridge files, and the folders of nested workspaces, which are never entered.
struct UseCasesOwnership: Sendable {
  private let scopeFolders: Set<WorkspacePath>
  private let ownedFiles: Set<WorkspacePath>

  /// What the groups file and the bridge file of the root are called (chapters 03 and 10).
  static let rootFileNames = ["use-case-groups.yml", "use-cases-bridge.yml"]

  /// Reads the ownership out of the loaded scopes.
  init(_ workspace: LoadedWorkspace) {
    var owned = Set<WorkspacePath>()

    for scope in workspace.scopes {
      owned.insert(scope.discovered.configuration)
      owned.formUnion(scope.discovered.definitionFiles)
    }

    for name in Self.rootFileNames {
      owned.insert(WorkspacePath.root.appending(literal: name))
    }

    ownedFiles = owned
    scopeFolders = Set(workspace.scopes.map(\.discovered.directory))
  }

  /// Every file that is Use Cases' own, sorted by path: what a links transformer is told to leave
  /// alone (chapter 10 §11).
  var files: [WorkspacePath] {
    ownedFiles.sorted()
  }

  /// Whether this file is Use Cases' own.
  func owns(_ file: WorkspacePath) -> Bool {
    ownedFiles.contains(file)
  }

  /// Whether this folder is another workspace, which this one never enters. A folder holding a
  /// `use-cases.yml` that is not one of this workspace's scopes can only be one: loading would
  /// have made it a scope, or refused the workspace, otherwise.
  func isNestedWorkspace(
    _ folder: WorkspacePath,
    listing: [FileEntry],
  ) -> Bool {
    guard !folder.isRoot, !scopeFolders.contains(folder) else {
      return false
    }

    return listing.contains { entry in
      entry.kind == .file
        && entry.name.isExactlyEqual(to: DiscoveredScope.configurationFileName)
    }
  }
}
