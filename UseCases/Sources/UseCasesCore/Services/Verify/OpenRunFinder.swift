import Foundation

/// Reads `runs/` for the runs that have a start stamp and no marker.
struct OpenRunFinder: OpenRunFinding {
  private let access: any StoreFileAccessing
  private let checker: any SchemaChecking

  init(
    access: any StoreFileAccessing,
    checker: any SchemaChecking,
  ) {
    self.access = access
    self.checker = checker
  }

  /// A finder over the real file system that checks start stamps against the bundled schema.
  init(loader: any StoreSchemaLoading =
    BundledStoreSchemaLoader()) throws(StoreSchemaLoadingError)
  {
    try self.init(
      access: StoreFileAccess(
        fileSystem: LocalFileSystem(),
        json: JSONReader(),
      ),
      checker: loader.loadChecker(
        for: .start,
        unknownMembers: .ignore,
      ),
    )
  }

  func openRuns(in workspace: URL) throws(StoreProblem) -> OpenRuns {
    let runs = StoreFile(workspace: workspace).appending(StoreLayout.runsFolder)

    guard try access.kind(of: runs) == .directory else {
      return OpenRuns(
        open: [],
        damaged: [],
        records: [],
      )
    }

    var identifiers: [RunIdentifier] = []
    for entry in try access.entries(in: runs) where entry.kind == .directory && entry.isNameUTF8 {
      if let identifier = try? RunIdentifier(validating: entry.name) {
        identifiers.append(identifier)
      }
    }

    var open: [OpenVerifyRun] = []
    var damaged: [DamagedRun] = []
    var records: [RunIdentifier] = []

    for identifier in identifiers.sorted() {
      switch try find(identifier, in: workspace) {
      case let .open(run):
        open.append(run)
      case let .damaged(run):
        damaged.append(run)
      case let .openRecord(record):
        records.append(record)
      case .sealed, .missing:
        continue
      }
    }

    return OpenRuns(
      open: open,
      damaged: damaged,
      records: records,
    )
  }

  func find(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) throws(StoreProblem) -> FoundRun {
    let folder = StoreFile(workspace: workspace)
      .appending(StoreLayout.runsFolder)
      .appending(identifier.text)

    guard try access.kind(of: folder) == .directory else {
      return .missing
    }
    guard try access.kind(of: folder.appending(StoreLayout.completionFile)) == nil else {
      return .sealed
    }

    let file = folder.appending(StoreLayout.startFile)

    guard let kind = try access.kind(of: file) else {
      return try withoutStamp(
        identifier,
        folder: folder,
      )
    }
    guard kind == .file else {
      return damaged(
        identifier,
        .corrupt(file.location, "it is not a regular file"),
        canBeClosed: false,
      )
    }

    do {
      let stamp = try readStamp(file)

      guard stamp.identifier == identifier else {
        return damaged(
          identifier,
          .corrupt(file.location, "its run_id \(stamp.identifier) is not the run's"),
          canBeClosed: true,
        )
      }

      return .open(OpenVerifyRun(stamp: stamp))
    } catch {
      return damaged(
        identifier,
        error,
        canBeClosed: true,
      )
    }
  }

  /// A run folder with no start stamp: a record run, which never has one, or a verify run that
  /// lost it. Only the manifest says which.
  private func withoutStamp(
    _ identifier: RunIdentifier,
    folder: StoreFile,
  ) throws(StoreProblem) -> FoundRun {
    let manifest = folder.appending(StoreLayout.manifestFile)
    let kind: String?

    do {
      kind = try manifestKind(of: manifest)
    } catch {
      return damaged(
        identifier,
        error,
        canBeClosed: false,
      )
    }

    switch kind {
    case RunKind.record.rawValue:
      return .openRecord(identifier)
    case RunKind.verify.rawValue:
      return damaged(
        identifier,
        .corrupt(folder.appending(StoreLayout.startFile).location, "the file is missing"),
        canBeClosed: false,
      )
    default:
      return damaged(
        identifier,
        .corrupt(manifest.location, "its kind is neither verify nor record"),
        canBeClosed: false,
      )
    }
  }

  private func manifestKind(of manifest: StoreFile) throws(StoreProblem) -> String? {
    let value = try access.document(
      access.requiredBytes(of: manifest),
      in: manifest,
    )

    do {
      return try AuthoredObject(value, at: "").optionalString("kind")
    } catch {
      throw .corrupt(manifest.location, error.description)
    }
  }

  private func damaged(
    _ identifier: RunIdentifier,
    _ problem: StoreProblem,
    canBeClosed: Bool,
  ) -> FoundRun {
    .damaged(
      DamagedRun(
        identifier: identifier,
        problem: problem,
        canBeClosed: canBeClosed,
      ),
    )
  }

  private func readStamp(_ file: StoreFile) throws(StoreProblem) -> StartStamp {
    let value = try access.document(
      access.requiredBytes(of: file),
      in: file,
    )

    guard checker.check(value).isEmpty else {
      throw .corrupt(file.location, "it breaks the start schema")
    }

    do {
      return try StartStamp(authored: AuthoredObject(value, at: ""))
    } catch {
      throw .corrupt(file.location, error.description)
    }
  }
}
