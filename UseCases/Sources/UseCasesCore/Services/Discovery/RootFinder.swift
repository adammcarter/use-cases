import Foundation

/// Finds the root by looking at `use-cases.yml` files. Folders are canonicalised first (chapter
/// 09 §4), so walking up follows the real folders, not the spelling the caller used.
struct RootFinder: RootFinding {
  private let fileSystem: any FileSystemReading
  private let settingsLoader: any ScopeSettingsLoading

  init(
    fileSystem: any FileSystemReading,
    settingsLoader: any ScopeSettingsLoading,
  ) {
    self.fileSystem = fileSystem
    self.settingsLoader = settingsLoader
  }

  func findRoot(from start: URL) throws(RootFindingError) -> WorkspaceRoot {
    var folder = fileSystem.canonicalLocation(of: start)

    while true {
      if let settings = try settings(inFolder: folder), settings.isRoot {
        return WorkspaceRoot(
          directory: folder,
          settings: settings,
        )
      }

      guard folder.path != "/" else {
        throw .noRootFound(startingAt: start)
      }

      folder = fileSystem.canonicalLocation(of: folder.deletingLastPathComponent())
    }
  }

  func requireRoot(at folder: URL) throws(RootFindingError) -> WorkspaceRoot {
    let canonical = fileSystem.canonicalLocation(of: folder)

    guard let settings = try settings(inFolder: canonical) else {
      throw .noConfiguration(canonical)
    }

    guard settings.isRoot else {
      throw .notTheRoot(canonical)
    }

    return WorkspaceRoot(
      directory: canonical,
      settings: settings,
    )
  }

  /// The folder's settings, or `nil` when it holds no `use-cases.yml` file.
  private func settings(inFolder folder: URL) throws(RootFindingError) -> ScopeSettings? {
    let file = folder.appendingPathComponent(DiscoveredScope.configurationFileName)

    // Cheap and allowed in a folder that cannot be listed; it may still be a name the file
    // system found by ignoring case or Unicode form, so the folder's listing has the last word.
    let found: FileEntryKind?

    do {
      found = try fileSystem.kindOfItem(at: file)
    } catch {
      throw .unreadableConfiguration(
        folder: folder,
        reason: .unreadable(error),
      )
    }

    guard found != nil else {
      return nil
    }

    let entries: [FileEntry]

    do {
      entries = try fileSystem.entries(in: folder)
    } catch {
      throw .unreadableConfiguration(
        folder: folder,
        reason: .unreadable(error),
      )
    }

    guard
      let entry = entries.first(where: { entry in
        entry.name.isExactlyEqual(to: DiscoveredScope.configurationFileName)
      })
    else {
      return nil
    }

    if entry.kind == .symlink {
      throw .configurationIsSymlink(folder)
    }

    guard entry.kind == .file else {
      return nil
    }

    do {
      return try settingsLoader.loadSettings(
        at: file,
        path: .root.appending(literal: DiscoveredScope.configurationFileName),
      )
    } catch {
      throw .unreadableConfiguration(
        folder: folder,
        reason: error,
      )
    }
  }
}
