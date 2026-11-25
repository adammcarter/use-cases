/// Finds paths by listing folders, one name at a time, from the workspace root.
struct ExactPathFinder: ExactPathFinding {
  let fileSystem: any FileSystemReading

  func find(
    _ path: WorkspacePath,
    in context: DiscoveryContext,
    listings: inout FolderListings,
  ) throws(ExactPathError) -> FileEntryKind {
    let names = path.segments
    var folder = WorkspacePath.root
    var kind = FileEntryKind.directory

    for (index, name) in names.enumerated() {
      let entry = try entry(
        named: name,
        in: folder,
        context: context,
        listings: &listings,
      )

      kind = entry.kind

      guard index < names.count - 1 else {
        break
      }

      folder = try descend(
        into: entry,
        in: folder,
      )
    }

    return kind
  }

  /// The entry with exactly this name, or why there is none.
  private func entry(
    named name: String,
    in folder: WorkspacePath,
    context: DiscoveryContext,
    listings: inout FolderListings,
  ) throws(ExactPathError) -> FileEntry {
    let entries: [FileEntry]

    do {
      entries = try listings.entries(
        in: folder,
        context: context,
        fileSystem: fileSystem,
      )
    } catch {
      throw .unreadableFolder(folder, error)
    }

    if let exact = entries.first(where: { entry in
      entry.name.isExactlyEqual(to: name)
    }) {
      return exact
    }

    let alike = entries
      .filter { entry in
        entry.name.isLooselyEqual(to: name)
      }
      .sorted { lhs, rhs in
        lhs.name.precedesExactly(rhs.name)
      }

    guard let first = alike.first else {
      throw .missing
    }

    throw .spelledDifferently(
      written: name,
      onDisk: first.name,
    )
  }

  /// The folder an entry in the middle of a path stands for.
  private func descend(
    into entry: FileEntry,
    in folder: WorkspacePath,
  ) throws(ExactPathError) -> WorkspacePath {
    guard let next = try? folder.appending(entry: entry) else {
      throw .missing
    }

    switch entry.kind {
    case .directory:
      return next
    case .symlink:
      throw .behindSymlink(next)
    case .file, .other:
      throw .missing
    }
  }
}
