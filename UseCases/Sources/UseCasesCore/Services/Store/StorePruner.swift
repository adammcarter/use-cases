import Foundation

/// Plans and removes superseded runs on the real file system (chapter 12 §31).
public struct StorePruner: StorePruning {
  private let fingerprinter: any RouteFingerprintComputing
  private let reading: Result<any StoreReading, StoreSchemaLoadingError>
  private let measurer: any StoreMeasuring
  private let lock: any RunLocking
  private let remover: any StoreFolderRemoving

  /// A pruner over the real file system, reading runs against the bundled schemas.
  public init() {
    self.init(
      fingerprinter: RouteFingerprintComputer(),
      reading: Result { () throws(StoreSchemaLoadingError) -> any StoreReading in
        try StoreReader()
      },
      measurer: StoreMeasurer(),
      lock: FlockRunLock(),
      remover: LocalStoreFolderRemover(),
    )
  }

  init(
    fingerprinter: any RouteFingerprintComputing = RouteFingerprintComputer(),
    reading: Result<any StoreReading, StoreSchemaLoadingError>,
    measurer: any StoreMeasuring,
    lock: any RunLocking,
    remover: any StoreFolderRemoving,
  ) {
    self.fingerprinter = fingerprinter
    self.reading = reading
    self.measurer = measurer
    self.lock = lock
    self.remover = remover
  }

  public func plan(
    for workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(StorePruningError) -> PrunePlan {
    let fingerprints = fingerprinter.fingerprints(
      of: workspace,
      links: links,
    )

    guard !fingerprints.isInvalid else {
      throw .invalidWorkspace(problems: fingerprints.problems)
    }

    return try plan(
      in: workspace.root,
      at: fingerprints.current,
    )
  }

  /// The plan for the store of a workspace root, keeping what status uses for these routes.
  func plan(
    in root: URL,
    at routes: [RouteAtFingerprint] = [],
  ) throws(StorePruningError) -> PrunePlan {
    let history = try readHistory(in: root)

    return PrunePlan(
      runs: history.supersededRuns(
        keeping: history.runsInUse(at: routes),
      ).map { run in
        PrunableRun(
          identifier: run.text,
          bytes: measurer.bytes(below: Self.folder(of: run.text, in: root)),
        )
      },
      leftovers: leftovers(in: root),
    )
  }

  private func readHistory(in root: URL) throws(StorePruningError) -> StoreHistory {
    switch reading {
    case let .success(reader):
      do {
        return try reader.readHistory(in: root)
      } catch {
        switch error {
        case let .damaged(problems):
          throw .unreadable(problems: problems.map(\.description))
        }
      }
    case let .failure(error):
      throw .unreadable(problems: ["the store's schemas could not be loaded: \(error)"])
    }
  }

  /// The folders an interrupted prune moved out of `runs/` and never deleted: prune's own, so it
  /// removes them whatever they hold.
  private func leftovers(in root: URL) -> [PruneLeftover] {
    let runs = Self.runsFolder(in: root)

    return remover.folderNames(in: runs).filter { name in
      name.hasPrefix(Self.asidePrefix)
        && (try? RunIdentifier(validating: String(name.dropFirst(Self.asidePrefix.count)))) != nil
    }.map { name in
      PruneLeftover(
        location: "\(StoreLayout.runsLocation)/\(name)",
        bytes: measurer.bytes(below: runs.appendingPathComponent(name)),
      )
    }
  }

  public func remove(
    _ plan: PrunePlan,
    from workspace: LoadedWorkspace,
  ) -> PruneOutcome {
    remove(
      plan,
      in: workspace.root,
    )
  }

  /// As `remove(_:from:)`, for the store of a workspace root.
  func remove(
    _ plan: PrunePlan,
    in root: URL,
  ) -> PruneOutcome {
    var removed: [PrunableRun] = []
    var kept: [PrunableRun] = []
    var leftOver: [PruneLeftover] = []
    var notes: [String] = []

    let leftovers = removeLeftovers(
      plan.leftovers,
      in: root,
      notes: &notes,
    )

    var unsettled: [(run: PrunableRun, removal: Removal)] = []

    for run in plan.runs {
      let removal = removeRun(
        run,
        in: root,
      )

      switch removal {
      case .removed:
        removed.append(run)
      case .leftOver, .kept:
        unsettled.append((run, removal))
      case .gone:
        break
      }
    }

    // Another prune may have been removing the same runs: a run it took away since is passed
    // over without a word (chapter 12 §30), so each note is written only for what is still there.
    for (run, removal) in unsettled {
      let aside = Self.runsFolder(in: root)
        .appendingPathComponent(Self.asidePrefix + run.identifier)

      switch removal {
      case let .leftOver(note) where remover.exists(aside):
        leftOver.append(PruneLeftover(
          location: "\(StoreLayout.runsLocation)/\(Self.asidePrefix)\(run.identifier)",
          bytes: run.bytes,
        ))
        notes.append(note)
      case let .kept(note) where remover.exists(Self.folder(of: run.identifier, in: root)):
        kept.append(run)
        notes.append(note)
      default:
        break
      }
    }

    return PruneOutcome(
      removed: removed,
      leftovers: leftovers,
      kept: kept,
      leftOver: leftOver,
      notes: notes,
    )
  }

  private func removeLeftovers(
    _ leftovers: [PruneLeftover],
    in root: URL,
    notes: inout [String],
  ) -> [PruneLeftover] {
    leftovers.filter { leftover in
      let name = String(leftover.location.dropFirst(StoreLayout.runsLocation.count + 1))

      do throws(StoreFolderError) {
        try remover.delete(Self.runsFolder(in: root).appendingPathComponent(name))

        return true
      } catch {
        if remover.exists(Self.runsFolder(in: root).appendingPathComponent(name)) {
          notes.append("\(leftover.location) could not be deleted: \(error.reason)")
        }

        return false
      }
    }
  }

  private enum Removal {
    case removed
    case leftOver(String)
    case kept(String)

    /// Another prune removed the run first: nothing to say.
    case gone
  }

  /// One run: held by its lock while its folder leaves `runs/`, so a process finishing or
  /// sealing it can never meet it half gone, and no reader ever sees part of it. A run prune keeps
  /// is left exactly as it was: a lock file prune made in it is taken away again.
  private func removeRun(
    _ run: PrunableRun,
    in root: URL,
  ) -> Removal {
    let folder = Self.folder(of: run.identifier, in: root)
    let aside = Self.runsFolder(in: root).appendingPathComponent(Self.asidePrefix + run.identifier)
    let lockFile = folder.appendingPathComponent(StoreLayout.runLockFile)
    let hadLockFile = remover.exists(lockFile)

    let held: HeldRunLock?

    do {
      held = try lock.acquire(run: folder)
    } catch {
      guard remover.exists(folder) else {
        return .gone
      }

      return .kept("run \(run.identifier) was kept: \(Self.reason(error))")
    }

    guard let held else {
      return .kept("run \(run.identifier) is in use by another process, so it was kept")
    }

    do {
      try remover.move(
        folder,
        to: aside,
      )
    } catch {
      held.release()

      if !hadLockFile {
        try? remover.delete(lockFile)
      }

      guard remover.exists(folder) else {
        return .gone
      }

      return .kept("run \(run.identifier) was kept: \(error.reason)")
    }

    held.release()

    do {
      try remover.delete(aside)
    } catch {
      return .leftOver(
        "run \(run.identifier) is out of the store, but its folder "
          + "\(StoreLayout.runsLocation)/\(aside.lastPathComponent) could not be deleted "
          + "(\(error.reason)); the next prune removes it",
      )
    }

    return .removed
  }

  /// What a person reads of a lock that could not be taken.
  private static func reason(_ error: StoreWritingError) -> StoreFolderError {
    guard case let .unwritable(_, reason) = error else {
      return StoreFolderError(reason: "\(error)")
    }

    return StoreFolderError(reason: reason)
  }

  /// The name a run's folder is moved to before its bytes are deleted: a temporary name, which
  /// readers pass over (chapter 12 §22).
  static let asidePrefix = StoreLayout.temporaryRunPrefix + "prune-"

  private static func runsFolder(in root: URL) -> URL {
    root.appendingPathComponent(StoreLayout.storeFolder)
      .appendingPathComponent(StoreLayout.runsFolder)
  }

  private static func folder(
    of identifier: String,
    in root: URL,
  ) -> URL {
    runsFolder(in: root).appendingPathComponent(identifier)
  }
}
