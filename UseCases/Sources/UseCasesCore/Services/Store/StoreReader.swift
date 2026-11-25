import Foundation

/// Reads `<root>/.use-cases/runs/` into a ``StoreHistory`` (chapter 12 §36).
struct StoreReader: StoreReading {
  private let access: any StoreFileAccessing
  private let runReader: any RunFolderReading

  init(
    access: any StoreFileAccessing,
    runReader: any RunFolderReading,
  ) {
    self.access = access
    self.runReader = runReader
  }

  /// A reader over the real file system, checking runs against the bundled schemas.
  init(
    fileSystem: any FileSystemReading = LocalFileSystem(),
    hasher: any Hashing = SHA256Hasher(),
    json: any JSONReading = JSONReader(),
    loader: any StoreSchemaLoading = BundledStoreSchemaLoader(),
  ) throws(StoreSchemaLoadingError) {
    let access = StoreFileAccess(
      fileSystem: fileSystem,
      json: json,
    )

    try self.init(
      access: access,
      runReader: RunFolderReader(
        access: access,
        hasher: hasher,
        checks: StoreChecks(loader: loader),
      ),
    )
  }

  func readHistory(in workspace: URL) throws(StoreReadingError) -> StoreHistory {
    var problems = StoreProblemLog()

    let runs = problems.attempt { () throws(StoreProblem) in
      try runFolders(in: workspace)
    }

    var sealed: [StoredRun] = []
    var unfinished: [UnfinishedRun] = []

    for folder in runs?.identifiers ?? [] {
      let outcome = runReader.readRun(
        folder,
        in: workspace,
      )

      // A run prune removed after the listing is gone whole, never damaged, unfinished or sealed
      // with a missing report: a reader sees the whole run or none of it (chapter 12 §30).
      if isGone(folder, in: workspace) {
        continue
      }

      switch outcome {
      case let .sealed(run):
        sealed.append(run)
      case let .unfinished(run):
        unfinished.append(run)
      case let .damaged(found):
        problems.add(found)
      }
    }
    problems.add(runs?.strays ?? [])

    guard problems.isClean else {
      throw .damaged(problems.problems.sorted())
    }

    return StoreHistory(
      runs: sealed,
      unfinishedRuns: unfinished,
    )
  }

  /// Whether a run's folder has left `runs/` since it was listed.
  private func isGone(
    _ run: RunIdentifier,
    in workspace: URL,
  ) -> Bool {
    let folder = StoreFile(workspace: workspace)
      .appending(StoreLayout.runsFolder)
      .appending(run.text)

    return (try? access.kind(of: folder)) == .some(nil)
  }

  /// The run folders of the store, and every entry of `runs/` that is not one. A store with no
  /// `runs/` folder has none of either, which is valid.
  private func runFolders(in workspace: URL) throws(StoreProblem) -> RunFolderListing {
    let store = StoreFile(workspace: workspace)
    let runs = store.appending(StoreLayout.runsFolder)

    guard try isFolderOrAbsent(store), try isFolderOrAbsent(runs) else {
      return RunFolderListing(
        identifiers: [],
        strays: [],
      )
    }

    var identifiers: [RunIdentifier] = []
    var strays: [StoreProblem] = []

    for entry in try access.entries(in: runs) {
      if let identifier = Self.identifier(of: entry) {
        identifiers.append(identifier)
      } else if !Self.isTemporary(entry) {
        strays.append(StoreProblem(
          location: runs.location + "/" + entry.name,
          reason: .notARunFolder,
        ))
      }
    }

    return RunFolderListing(
      identifiers: identifiers.sorted(),
      strays: strays,
    )
  }

  /// Whether the place is a folder. A place with nothing there is fine and has nothing in it.
  private func isFolderOrAbsent(_ file: StoreFile) throws(StoreProblem) -> Bool {
    switch try access.kind(of: file) {
    case nil:
      false
    case .directory?:
      true
    case .file?, .symlink?, .other?:
      throw StoreProblem(
        location: file.location,
        reason: .notAFolder,
      )
    }
  }

  private static func identifier(of entry: FileEntry) -> RunIdentifier? {
    guard entry.kind == .directory, entry.isNameUTF8 else {
      return nil
    }

    return try? RunIdentifier(validating: entry.name)
  }

  private static func isTemporary(_ entry: FileEntry) -> Bool {
    entry.kind == .directory && entry.isNameUTF8
      && entry.name.hasPrefix(StoreLayout.temporaryRunPrefix)
  }
}
