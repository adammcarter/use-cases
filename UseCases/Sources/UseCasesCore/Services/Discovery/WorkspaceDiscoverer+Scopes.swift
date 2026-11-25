import Foundation

extension WorkspaceDiscoverer {
  /// Every folder below the root, apart from excluded folders, nested workspaces and symlinks,
  /// looking for `use-cases.yml`.
  func walkScopes(context: DiscoveryContext) -> ScopeWalkState {
    var state = ScopeWalkState()
    var pending: [WorkspacePath] = [.root]

    while let directory = pending.popLast() {
      let entries: [FileEntry]

      do {
        entries = try fileSystem.entries(in: context.url(for: directory))
      } catch {
        state.diagnostics.append(.unreadableDirectory(directory, because: error))
        continue
      }

      reportSpelledDifferently(
        in: directory,
        entries: entries,
        state: &state,
      )

      let entersFolder =
        directory.isRoot
          || examineConfiguration(
            in: directory,
            entries: entries,
            context: context,
            state: &state,
          )

      guard entersFolder else {
        continue
      }

      for entry in entries where entry.kind == .directory {
        guard let child = try? directory.appending(entry: entry) else {
          state.diagnostics.append(
            unspellableFolderDiagnostic(
              entry,
              in: directory,
              context: context,
            ),
          )
          continue
        }

        if !context.isExcluded(child) {
          pending.append(child)
        }
      }
    }

    return state
  }

  /// What to say about a folder whose name no workspace path can spell, so it cannot be entered:
  /// a warning, or an error when a `use-cases.yml` is somewhere inside it (chapter 09 §6.2).
  private func unspellableFolderDiagnostic(
    _ entry: FileEntry,
    in directory: WorkspacePath,
    context: DiscoveryContext,
  ) -> Diagnostic {
    let holdsScope = fileSystem.holdsFile(
      named: DiscoveredScope.configurationFileName,
      below: entry,
      in: context.url(for: directory),
    )

    if holdsScope {
      return .scopeInUnspellableFolder(entry.displayName, in: directory)
    }

    return .unspellableName(entry.displayName, in: directory)
  }

  /// A file that is `use-cases.yml` when case or Unicode form is ignored, but is not spelled so,
  /// is INVALID, never skipped, and the message names the spelling on disk (chapter 09 §11.1).
  /// That holds beside a real `use-cases.yml` too. It is not read: it is not a scope.
  private func reportSpelledDifferently(
    in directory: WorkspacePath,
    entries: [FileEntry],
    state: inout ScopeWalkState,
  ) {
    for entry in entries where entry.kind != .directory {
      guard
        entry.name.isLooselyEqual(to: DiscoveredScope.configurationFileName),
        !entry.name.isExactlyEqual(to: DiscoveredScope.configurationFileName),
        let found = try? directory.appending(entry: entry)
      else {
        continue
      }

      state.diagnostics.append(.configurationSpelledDifferently(found))
    }
  }

  /// Records what the folder's `use-cases.yml`, if it has one, says. Returns whether the walk
  /// goes on into the folder: a nested workspace is never entered.
  private func examineConfiguration(
    in directory: WorkspacePath,
    entries: [FileEntry],
    context: DiscoveryContext,
    state: inout ScopeWalkState,
  ) -> Bool {
    let configuration = directory.appending(literal: DiscoveredScope.configurationFileName)

    guard
      let entry = entries.first(where: { entry in
        entry.name.isExactlyEqual(to: DiscoveredScope.configurationFileName)
      })
    else {
      return true
    }

    // A symlink is never read. A folder or other thing of that name is not a configuration.
    if entry.kind == .symlink {
      state.unreadable.insert(directory)
      state.diagnostics.append(.configurationIsSymlink(configuration))
      return true
    }

    guard entry.kind == .file else {
      return true
    }

    do {
      let settings = try settingsLoader.loadSettings(
        at: context.url(for: configuration),
        path: configuration,
      )

      if settings.isRoot {
        state.nestedWorkspaces.insert(directory)
        return false
      }

      state.settings[directory] = settings
    } catch {
      state.unreadable.insert(directory)
      state.diagnostics += Diagnostic.configuration(configuration, refused: error)
    }

    return true
  }
}
