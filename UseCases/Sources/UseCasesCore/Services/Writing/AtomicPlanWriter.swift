import Foundation

/// Writes plans on the machine's file system, all or nothing. Every new file is written first
/// beside its target, flushed and with its permissions; only when all are staged is each swapped
/// in by a rename (a new file by a link, which never replaces one), and the originals of replaced
/// and deleted files are kept until the end. A failure part way renames the originals back and
/// removes what was staged and made, so no file is left half changed.
///
/// One writer at a time works on a workspace, and a file that holds anything but what its change
/// expected is never replaced or deleted: the change someone else made in between is kept, and
/// the plan is refused.
public struct AtomicPlanWriter: PlanWriting {
  private let preflight: any ChangeChecking
  private let fileSystem: any FileSystemReading

  /// One change with the place it is made.
  private struct Target {
    let change: FileChange
    let folder: URL

    var file: URL {
      folder.appendingPathComponent(change.path)
    }
  }

  /// Makes the writer that uses the real file system.
  public init() {
    self.init(fileSystem: LocalFileSystem())
  }

  init(fileSystem: any FileSystemReading) {
    self.init(
      fileSystem: fileSystem,
      preflight: PlanPreflight(fileSystem: fileSystem),
    )
  }

  /// - Parameters:
  ///   - fileSystem: What the writer reads and writes through.
  ///   - preflight: Refuses a change that cannot be made where it is asked.
  init(
    fileSystem: any FileSystemReading,
    preflight: any ChangeChecking,
  ) {
    self.preflight = preflight
    self.fileSystem = fileSystem
  }

  public func apply(
    _ writes: [FolderWrite],
    lockingIn workspace: URL,
  ) throws(PlanWritingError) {
    // A folder that is not a workspace yet, which `init` is making one of, has no work of anyone's
    // to lose, and gets no `.use-cases/` folder before the files `init` writes (chapter 17).
    let isWorkspace = (try? fileSystem.kindOfItem(
      at: workspace.appendingPathComponent(DiscoveredScope.configurationFileName),
    )) == .file
    let lock = isWorkspace ? try WriteLock.acquire(in: workspace) : nil

    defer {
      lock?.release()
    }

    try apply(writes)
  }

  private func apply(_ writes: [FolderWrite]) throws(PlanWritingError) {
    let targets = writes.flatMap { write in
      write.plan.changes.map { change in
        Target(
          change: change,
          folder: write.folder,
        )
      }
    }

    for target in targets {
      try preflight.check(
        target.change,
        in: target.folder,
      )
      try confirmUnchanged(target)
    }

    var journal = PlanJournal()

    do {
      try makeFolders(
        for: targets,
        journal: &journal,
      )

      let staged = try stage(
        targets,
        journal: &journal,
      )

      try swap(
        targets,
        staged: staged,
        journal: &journal,
      )
    } catch {
      journal.undo()

      throw error
    }

    journal.finish()
  }

  /// Refuses a file to replace or delete that holds anything else than the change expected.
  private func confirmUnchanged(_ target: Target) throws(PlanWritingError) {
    guard target.change.action != .create, let expected = target.change.expected else {
      return
    }

    let found: [UInt8]

    do {
      found = try fileSystem.readBytes(at: target.file)
    } catch .notFound {
      throw .changed(path: target.change.path)
    } catch {
      throw .unwritable(
        location: target.file.path,
        reason: error.description,
      )
    }

    guard found == expected else {
      throw .changed(path: target.change.path)
    }
  }

  /// Every folder above a new file that is not there yet.
  private func makeFolders(
    for targets: [Target],
    journal: inout PlanJournal,
  ) throws(PlanWritingError) {
    var known: Set<String> = []

    for target in targets where target.change.action == .create {
      for folder in target.change.workspacePath.ancestors.reversed()
        where !folder.isRoot && known.insert(target.folder.path + "/" + folder.text).inserted
      {
        let location = target.folder.appendingPathComponent(folder.text)

        if try PlanFiles.makeFolder(location) {
          journal.madeFolder(location)
        }
      }
    }
  }

  /// The new bytes of every file to create or replace, written beside its target; the staged
  /// file for the target at each index, or `nil` where nothing is written.
  private func stage(
    _ targets: [Target],
    journal: inout PlanJournal,
  ) throws(PlanWritingError) -> [URL?] {
    var staged: [URL?] = []

    for target in targets {
      switch target.change.action {
      case .create:
        let file = try stage(
          target,
          permissions: PlanFiles.permissions(isExecutable: target.change.isExecutable),
          keeping: nil,
          journal: &journal,
        )
        staged.append(file)
      case .replace:
        // A replaced file keeps its permissions, and its owner where the system allows.
        let existing = try PlanFiles.attributes(of: target.file)

        let file = try stage(
          target,
          permissions: existing.permissions,
          keeping: existing,
          journal: &journal,
        )
        staged.append(file)
      case .delete:
        staged.append(nil)
      }
    }

    return staged
  }

  private func stage(
    _ target: Target,
    permissions: mode_t,
    keeping existing: PlanFiles.Attributes?,
    journal: inout PlanJournal,
  ) throws(PlanWritingError) -> URL {
    let file = try PlanFiles.stage(
      target.change.bytes,
      beside: target.file,
      permissions: permissions,
      owner: existing,
    )
    journal.left(file)

    return file
  }

  private func swap(
    _ targets: [Target],
    staged: [URL?],
    journal: inout PlanJournal,
  ) throws(PlanWritingError) {
    for (target, file) in zip(targets, staged) {
      switch (target.change.action, file) {
      case let (.create, file?):
        try PlanFiles.addName(
          for: file,
          as: target.file,
        )
        journal.swapped(.created(target.file))
      case let (.replace, file?):
        let backup = try keepOriginal(
          of: target,
          journal: &journal,
        )
        journal.swapped(.replaced(target.file, backup: backup))

        try PlanFiles.move(
          file,
          to: target.file,
        )
      case (.delete, _):
        let backup = PlanFiles.sibling(
          of: target.file,
          kind: "bak",
        )
        journal.left(backup)

        try PlanFiles.move(
          target.file,
          to: backup,
        )
        journal.swapped(.deleted(target.file, backup: backup))
      default:
        continue
      }
    }
  }

  /// Another name for the file that is about to be replaced, so that the original is there to put
  /// back; where the system will not link, the file is moved aside instead.
  private func keepOriginal(
    of target: Target,
    journal: inout PlanJournal,
  ) throws(PlanWritingError) -> URL {
    let backup = PlanFiles.sibling(
      of: target.file,
      kind: "bak",
    )
    journal.left(backup)

    do {
      try PlanFiles.addName(
        for: target.file,
        as: backup,
      )
    } catch {
      try PlanFiles.move(
        target.file,
        to: backup,
      )
    }

    return backup
  }
}
