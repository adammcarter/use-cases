struct OwnedFileLocator: OwnedFileLocating {
  private let fileSystem: any FileSystemReading

  init(fileSystem: any FileSystemReading) {
    self.fileSystem = fileSystem
  }

  func locate(
    _ name: String,
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
    belowRoot: (WorkspacePath) -> Diagnostic,
  ) throws(FileSystemError) -> OwnedFileLocation {
    let listing = try fileSystem.entries(in: root.directory)
    var diagnostics = lookalikes(
      of: name,
      among: listing,
      in: .root,
    )

    for scope in scopes where !scope.discovered.isRoot {
      guard let entries = try? fileSystem.entries(in: root.location(of: scope.discovered.directory))
      else {
        continue
      }

      if entries.contains(where: { entry in
        isExactly(entry, named: name)
      }) {
        diagnostics.append(belowRoot(scope.discovered.directory.appending(literal: name)))
      }

      diagnostics += lookalikes(
        of: name,
        among: entries,
        in: scope.discovered.directory,
      )
    }

    return OwnedFileLocation(
      entry: listing.first { entry in
        isExactly(entry, named: name)
      },
      diagnostics: diagnostics,
    )
  }

  private func isExactly(
    _ entry: FileEntry,
    named name: String,
  ) -> Bool {
    entry.isNameUTF8 && entry.name.isExactlyEqual(to: name)
  }

  /// A file that is the name only when case or Unicode form is ignored is a problem naming the
  /// spelling on disk, never skipped; it is not read.
  private func lookalikes(
    of name: String,
    among entries: [FileEntry],
    in folder: WorkspacePath,
  ) -> [Diagnostic] {
    entries.compactMap { entry in
      guard
        entry.kind != .directory,
        entry.isNameUTF8,
        entry.name.isLooselyEqual(to: name),
        !entry.name.isExactlyEqual(to: name),
        let found = try? folder.appending(entry: entry)
      else {
        return nil
      }

      return .ownedFileSpelledDifferently(
        found,
        expected: name,
      )
    }
  }
}
