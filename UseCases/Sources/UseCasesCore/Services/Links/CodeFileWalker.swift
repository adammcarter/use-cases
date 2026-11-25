/// Walks the workspace on a file system and names every file the code scan reads.
struct CodeFileWalker: CodeFileWalking {
  let fileSystem: any FileSystemReading

  func walk(
    _ workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> CodeWalk {
    let ownership = UseCasesOwnership(workspace)
    var found = CodeWalk.empty
    var pending: [WorkspacePath] = [.root]

    while let folder = pending.popLast() {
      let entries: [FileEntry]

      do {
        entries = try fileSystem.entries(in: context.url(for: folder))
      } catch {
        found.diagnostics.append(.unreadableDirectory(folder, because: error))
        continue
      }

      if ownership.isNestedWorkspace(folder, listing: entries) {
        continue
      }

      for entry in entries {
        guard
          let path = path(
            of: entry,
            in: folder,
            found: &found,
          ),
          !context.isExcluded(path)
        else {
          continue
        }

        switch entry.kind {
        case .directory:
          pending.append(path)
        case .other:
          found.diagnostics.append(.specialFileSkipped(path))
        case .file, .symlink:
          if !ownership.owns(path) {
            found.files.append(
              WalkedFile(
                path: path,
                kind: entry.kind == .symlink ? .symlink : .file,
              ),
            )
          }
        }
      }
    }

    return found
  }

  /// The workspace path of an entry. A file whose name no path can spell is warned about; a
  /// folder is not, because loading warns about those.
  private func path(
    of entry: FileEntry,
    in folder: WorkspacePath,
    found: inout CodeWalk,
  ) -> WorkspacePath? {
    do {
      return try folder.appending(entry: entry)
    } catch {
      if entry.kind != .directory {
        found.diagnostics.append(
          .unspellableFile(
            entry.displayName,
            in: folder,
            because: error,
          ),
        )
      }

      return nil
    }
  }
}
