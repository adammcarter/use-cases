import Foundation

struct BridgeSettingsChecker: BridgeSettingsChecking {
  private let fileSystem: any FileSystemReading
  private let pathFinder: any ExactPathFinding

  init(
    fileSystem: any FileSystemReading,
    pathFinder: any ExactPathFinding,
  ) {
    self.fileSystem = fileSystem
    self.pathFinder = pathFinder
  }

  func check(
    _ settings: BridgeSettings,
    in root: WorkspaceRoot,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    var found: [Diagnostic] = []

    found += duplicates(
      among: settings.validations,
      file: file,
    )

    for (index, entry) in settings.links.enumerated() {
      found += check(
        entry.transformer,
        at: "links/\(index)/transformer",
        in: root,
        file: file,
      )
    }

    for (index, validation) in settings.validations.enumerated() {
      found += placeholders(
        in: validation.run ?? [],
        at: index,
        file: file,
      )
      found += check(
        validation.workingDirectory,
        at: index,
        in: root,
        file: file,
      )
      found += check(
        validation.transformer,
        at: "validations/\(index)/transformer",
        in: root,
        file: file,
      )
    }

    return found
  }

  private func duplicates(
    among validations: [BridgeValidation],
    file: WorkspacePath,
  ) -> [Diagnostic] {
    var firstSeen: [IdentifierSegment: Int] = [:]
    var found: [Diagnostic] = []

    for (index, validation) in validations.enumerated() {
      if let first = firstSeen[validation.identifier] {
        found.append(
          .duplicateValidation(
            validation.identifier,
            at: index,
            first: first,
            in: file,
          ),
        )
      } else {
        firstSeen[validation.identifier] = index
      }
    }

    return found
  }

  /// A word in braces in a run argument that is a near miss of `{report}`, so most likely a
  /// mistyped placeholder; every other word in braces is text and passes.
  private func placeholders(
    in run: [String],
    at index: Int,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    run.enumerated().flatMap { position, argument in
      RunPlaceholder.found(in: argument).filter { placeholder in
        placeholder.isNearMiss
      }.map { placeholder in
        Diagnostic.unknownPlaceholder(
          placeholder,
          at: "validations/\(index)/run/\(position)",
          in: file,
        )
      }
    }
  }

  private func check(
    _ directory: WorkspacePath?,
    at index: Int,
    in root: WorkspaceRoot,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    guard let directory else {
      return []
    }

    let reason = workingDirectoryProblem(
      directory,
      in: root,
    )

    guard let reason else {
      return []
    }

    return [
      .badWorkingDirectory(
        directory,
        because: reason,
        at: index,
        in: file,
      ),
    ]
  }

  /// Why a `working_dir` cannot be used, or `nil` when it can: it has to be a folder that is
  /// there under exactly this spelling, reached through no symlink, inside the workspace and
  /// outside the results store (chapter 04 "Path spelling" and "Symlinks", chapter 10 §7).
  private func workingDirectoryProblem(
    _ directory: WorkspacePath,
    in root: WorkspaceRoot,
  ) -> String? {
    // The store is named by any spelling the file system would take for it, not only the exact
    // one: on a Mac `.USE-CASES` is the same folder.
    if let first = directory.segments.first,
       first.isLooselyEqual(to: StoreLayout.storeFolder)
    {
      return "is the results store, which no command runs in"
    }

    switch lookup(
      directory,
      in: root,
    ) {
    case let .problem(reason):
      return reason
    case let .found(kind):
      switch kind {
      case .directory:
        break
      case .symlink:
        return "is a symlink, which is never followed"
      case .file, .other:
        return "is not a folder"
      }
    }

    let canonical = fileSystem.canonicalLocation(of: root.location(of: directory))
    let store = fileSystem.canonicalLocation(of: root.directory)
      .appendingPathComponent(StoreLayout.storeFolder)

    guard Self.isInside(canonical, folder: fileSystem.canonicalLocation(of: root.directory)) else {
      return "is outside the workspace"
    }
    guard !Self.isInside(canonical, folder: store) else {
      return "is inside the results store"
    }

    return nil
  }

  /// What stands at a path the file names, found by listing every folder on the way, so that
  /// the spelling is the one on disk and no symlink is followed.
  private func lookup(
    _ path: WorkspacePath,
    in root: WorkspaceRoot,
  ) -> PathLookup {
    var listings = FolderListings()
    let context = DiscoveryContext(
      rootDirectory: root.directory,
      builtInExcludes: [],
      configuredExcludes: [],
    )

    do {
      return try .found(
        pathFinder.find(
          path,
          in: context,
          listings: &listings,
        ),
      )
    } catch {
      switch error {
      case .missing:
        return .problem("does not exist")
      case let .spelledDifferently(written, onDisk):
        return .problem(
          "is spelled differently on disk: '\(written)' is '\(onDisk)'; paths must match "
            + "exactly, case and Unicode form included",
        )
      case let .behindSymlink(link):
        return .problem("passes through '\(link)', a symlink, which is never followed")
      case let .unreadableFolder(folder, failure):
        return .problem("cannot be looked at: the folder '\(folder)' \(failure)")
      }
    }
  }

  private func check(
    _ transformer: TransformerReference,
    at place: String,
    in root: WorkspaceRoot,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    switch transformer {
    case let .bundled(name):
      guard BundledTransformer.names.contains(name) else {
        return [
          .unknownBundledTransformer(
            name,
            at: place,
            in: file,
          ),
        ]
      }

      return []
    case let .program(program):
      return check(
        program,
        at: place,
        in: root,
        file: file,
      )
    }
  }

  private func check(
    _ program: WorkspacePath,
    at place: String,
    in root: WorkspaceRoot,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    guard let reason = programProblem(
      program,
      in: root,
    ) else {
      return []
    }

    return [
      .badTransformerProgram(
        program,
        because: reason,
        at: place,
        in: file,
      ),
    ]
  }

  /// Why a transformer program cannot be used, or `nil` when it can: a file that is there under
  /// exactly this spelling, reached through no symlink, and inside the workspace. A program that
  /// is itself a symlink is launched where it leads, which has to be a file inside the workspace.
  private func programProblem(
    _ program: WorkspacePath,
    in root: WorkspaceRoot,
  ) -> String? {
    let kind: FileEntryKind

    switch lookup(
      program,
      in: root,
    ) {
    case let .problem(reason):
      return reason
    case let .found(found):
      kind = found
    }

    if kind == .directory || kind == .other {
      return "is not a file"
    }

    let canonical = fileSystem.canonicalLocation(of: root.location(of: program))

    guard Self.isInside(canonical, folder: fileSystem.canonicalLocation(of: root.directory)) else {
      return "is outside the workspace"
    }

    // A symlink leads to a file or it leads nowhere a program can start.
    guard (try? fileSystem.kindOfItem(at: canonical)) == .file else {
      return "is not a file"
    }

    return nil
  }

  private static func isInside(
    _ location: URL,
    folder: URL,
  ) -> Bool {
    let inside = location.pathComponents
    let outside = folder.pathComponents

    return inside.count >= outside.count && Array(inside.prefix(outside.count)) == outside
  }
}
