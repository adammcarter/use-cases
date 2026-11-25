import Foundation

/// What can be known about a change before anything is written: whether the place it needs is
/// as the change expects (chapter 16 §17, command architecture §2).
struct PlanPreflight: ChangeChecking {
  private let fileSystem: any FileSystemReading

  init(fileSystem: any FileSystemReading) {
    self.fileSystem = fileSystem
  }

  func check(
    _ change: FileChange,
    in root: URL,
  ) throws(PlanWritingError) {
    try checkFolders(
      above: change.workspacePath,
      in: root,
    )

    let found = try kind(of: root.appendingPathComponent(change.path))

    switch change.action {
    case .create:
      if found != nil {
        throw .exists(path: change.path)
      }
    case .replace, .delete:
      // A file that was read when the plan was made and is gone now was changed by someone else.
      if found == nil, change.expected != nil {
        throw .changed(path: change.path)
      }

      if found != .file {
        throw .missing(path: change.path)
      }
    }
  }

  /// A folder above the file is there or absent; anything else in its place is in the way.
  private func checkFolders(
    above path: WorkspacePath,
    in root: URL,
  ) throws(PlanWritingError) {
    for folder in path.ancestors.reversed() where !folder.isRoot {
      switch try kind(of: root.appendingPathComponent(folder.text)) {
      case nil:
        return
      case .directory?:
        continue
      case .symlink?:
        throw .obstructed(
          path: folder.text,
          reason: "it is a symlink, not a folder",
        )
      case .file?, .other?:
        throw .obstructed(
          path: folder.text,
          reason: "it is a file, not a folder",
        )
      }
    }
  }

  private func kind(of location: URL) throws(PlanWritingError) -> FileEntryKind? {
    do {
      return try fileSystem.kindOfItem(at: location)
    } catch {
      throw .unwritable(
        location: location.path,
        reason: error.description,
      )
    }
  }
}
