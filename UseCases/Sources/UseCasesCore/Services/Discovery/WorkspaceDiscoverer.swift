import Foundation

/// Discovers scopes and definition files on a file system, reading each `use-cases.yml`
/// through a `ScopeSettingsLoading`.
struct WorkspaceDiscoverer: WorkspaceDiscovering {
  let fileSystem: any FileSystemReading
  let settingsLoader: any ScopeSettingsLoading

  func discover(root: WorkspaceRoot) -> WorkspaceDiscovery {
    var context = DiscoveryContext(
      rootDirectory: root.directory,
      builtInExcludes: DefaultDiscoveryExclusions.patterns,
      configuredExcludes: root.settings.excludes,
    )

    let walk = walkScopes(context: context)
    var diagnostics = walk.diagnostics

    var settings = walk.settings
    settings[.root] = root.settings

    let readable = Set(settings.keys)
    context.claimedDirectories = readable.union(walk.unreadable).union(walk.nestedWorkspaces)

    diagnostics += ownershipDiagnostics(
      settings: settings,
      scopeDirectories: readable.union(walk.unreadable).union(walk.nestedWorkspaces),
    )

    let rootScope = makeScope(
      at: .root,
      settings: root.settings,
      readableDirectories: readable,
      context: context,
      diagnostics: &diagnostics,
    )

    var descendants: [DiscoveredScope] = []

    for (directory, scopeSettings) in walk.settings {
      descendants.append(
        makeScope(
          at: directory,
          settings: scopeSettings,
          readableDirectories: readable,
          context: context,
          diagnostics: &diagnostics,
        ),
      )
    }

    let tree = ScopeTree(
      root: rootScope,
      descendants: descendants,
    )

    return WorkspaceDiscovery(
      scopeTree: tree,
      nestedWorkspaces: walk.nestedWorkspaces.sorted(),
      unreadableScopes: walk.unreadable.sorted(),
      // A folder both walks fail to list is one problem, reported once.
      diagnostics: Set(supersededWarningsRemoved(from: diagnostics, tree: tree)).sorted(),
    )
  }

  private func makeScope(
    at directory: WorkspacePath,
    settings: ScopeSettings,
    readableDirectories: Set<WorkspacePath>,
    context: DiscoveryContext,
    diagnostics: inout [Diagnostic],
  ) -> DiscoveredScope {
    DiscoveredScope(
      directory: directory,
      parent: directory.ancestors.first { ancestor in
        readableDirectories.contains(ancestor)
      },
      useCasesDirectory: directory.joining(settings.useCasesDirectory),
      definitionFiles: discoverDefinitions(
        ofScopeAt: directory,
        settings: settings,
        context: context,
        diagnostics: &diagnostics,
      ),
    )
  }

  /// A name no path can spell is a warning where it is skipped, and an error inside a
  /// `use_cases_dir`, which is read whole. The warning the folder walk gave there is dropped.
  private func supersededWarningsRemoved(
    from diagnostics: [Diagnostic],
    tree: ScopeTree,
  ) -> [Diagnostic] {
    let definitionFolders = tree.scopes.map(\.useCasesDirectory)

    return diagnostics.filter { diagnostic in
      guard diagnostic.code == "unspellable-name" else {
        return true
      }

      return !definitionFolders.contains { folder in
        diagnostic.file.isInsideOrEqual(to: folder)
      }
    }
  }
}
