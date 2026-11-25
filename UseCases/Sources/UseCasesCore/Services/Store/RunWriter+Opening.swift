import Foundation

extension RunWriter {
  func openRun(
    kind: RunKind,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun {
    try open(
      kind: kind,
      draft: nil,
      in: workspace,
      holdsLock: false,
    ).run
  }

  func openHeldRun(
    kind: RunKind,
    in workspace: URL,
  ) throws(StoreWritingError) -> HeldRun {
    try held(
      open(
        kind: kind,
        draft: nil,
        in: workspace,
        holdsLock: true,
      ),
    )
  }

  func openVerifyRun(
    _ draft: StartDraft,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun {
    try open(
      kind: .verify,
      draft: draft,
      in: workspace,
      holdsLock: false,
    ).run
  }

  func openHeldVerifyRun(
    _ draft: StartDraft,
    in workspace: URL,
  ) throws(StoreWritingError) -> HeldRun {
    try held(
      open(
        kind: .verify,
        draft: draft,
        in: workspace,
        holdsLock: true,
      ),
    )
  }

  private func held(_ opened: (run: OpenRun, lock: HeldRunLock?)) throws(StoreWritingError)
    -> HeldRun
  {
    guard let lock = opened.lock else {
      throw .unwritable(
        location: StoreLayout.location(of: opened.run.identifier),
        reason: "the run's lock was not taken",
      )
    }

    return HeldRun(
      run: opened.run,
      lock: lock,
    )
  }

  private func open(
    kind: RunKind,
    draft: StartDraft?,
    in workspace: URL,
    holdsLock: Bool,
  ) throws(StoreWritingError) -> (run: OpenRun, lock: HeldRunLock?) {
    let store = StoreFile(workspace: workspace)

    // Allocation metadata that cannot be used refuses before anything is made, so a refusal
    // leaves no `runs/` and no lock file behind. The mark is read again under the lock.
    _ = try highestAllocated(in: workspace)

    try files.ensureFolder(at: store.url)
    try files.ensureFolder(at: store.appending(StoreLayout.runsFolder).url)

    return try locks
      .locked(at: store.appending(Self.lockFile).url) { () throws(StoreWritingError) in
        try allocateRun(
          kind: kind,
          draft: draft,
          in: workspace,
          holdsLock: holdsLock,
        )
      }
  }

  /// The critical section of chapter 12 §9: read the mark, reserve a greater id, persist the
  /// mark, publish the run. It runs with the allocation lock held.
  private func allocateRun(
    kind: RunKind,
    draft: StartDraft?,
    in workspace: URL,
    holdsLock: Bool,
  ) throws(StoreWritingError) -> (run: OpenRun, lock: HeldRunLock?) {
    let store = StoreFile(workspace: workspace)
    let runs = store.appending(StoreLayout.runsFolder)

    let number = try allocator.next(
      above: highestAllocated(in: workspace),
    )
    let identifier = try identifier(of: number)
    let manifest = RunManifest(
      identifier: identifier,
      createdAt: clock.now().storeTimestamp,
      kind: kind,
      sources: draft?.sources ?? [],
      errors: [],
      diagnostics: [],
      unlinkedTests: [],
      notes: [],
    )

    // Everything is checked before the first byte is written.
    let manifestBytes = printer.pretty(manifest.document)
    _ = try validated(
      manifestBytes,
      against: checks.run,
      location: runs.appending(identifier.text).appending(StoreLayout.manifestFile).location,
    )

    let stamp = try stampBytes(
      of: draft,
      for: manifest,
      in: runs.appending(identifier.text),
    )

    try persistMark(
      of: identifier,
      in: store,
    )

    let lock = try publishRun(
      RunPublication(
        identifier: identifier,
        manifestBytes: manifestBytes,
        stamp: stamp,
        reportFolders: draft?.selected ?? [],
        holdsLock: holdsLock,
      ),
      in: runs,
    )

    return (
      run: OpenRun(
        workspace: workspace,
        manifest: manifest,
      ),
      lock: lock,
    )
  }

  /// The new high-water mark is on disk before the run can be seen.
  private func persistMark(
    of identifier: RunIdentifier,
    in store: StoreFile,
  ) throws(StoreWritingError) {
    let order = RunOrder(lastRunIdentifier: identifier)
    let orderFile = store.appending(StoreLayout.runOrderFile)

    _ = try validated(
      order.fileBytes,
      against: checks.runOrder,
      location: orderFile.location,
    )
    try files.replaceFile(
      order.fileBytes,
      at: orderFile.url,
    )
  }

  /// The greatest id the store has seen: the mark in `run-order.json` and the greatest run
  /// folder, whichever is greater. A store with neither has none (chapter 12 §9).
  private func highestAllocated(in workspace: URL) throws(StoreWritingError) -> RunNumber? {
    let runs = StoreFile(workspace: workspace).appending(StoreLayout.runsFolder)

    var highest: RunNumber?

    do {
      if let order = try orderReader.readRunOrder(in: workspace) {
        highest = RunNumber(identifier: order.lastRunIdentifier)
      }
    } catch {
      throw .allocation(error)
    }

    let hasRuns = try reading { () throws(StoreProblem) in
      try access.kind(of: runs) == .directory
    }

    // A store with no `runs/` yet has no folders to be above. Something else in its place is
    // reported when the folder is made.
    guard hasRuns else {
      return highest
    }

    let entries = try reading { () throws(StoreProblem) in
      try access.entries(in: runs)
    }

    for entry in entries where entry.kind == .directory && entry.isNameUTF8 {
      guard let identifier = try? RunIdentifier(validating: entry.name) else {
        continue
      }

      let found = RunNumber(identifier: identifier)

      if let current = highest, current >= found {
        continue
      }

      highest = found
    }

    return highest
  }

  /// The initial `run.json` and an empty `results.jsonl` appear together: they are made in a
  /// `.tmp-` folder, which is not a run, and the folder is renamed to the run's id.
  private func publishRun(
    _ publication: RunPublication,
    in runs: StoreFile,
  ) throws(StoreWritingError) -> HeldRunLock? {
    let identifier = publication.identifier
    let manifestBytes = publication.manifestBytes
    let stamp = publication.stamp
    let temporary = runs.appending(StoreLayout.temporaryRunPrefix + identifier.text)
    var lock: HeldRunLock?

    do {
      try files.ensureFolder(at: temporary.url)

      // The lock is taken in the staging folder, before the rename: the open file keeps it
      // through the rename, and the run is never visible without its holder.
      if publication.holdsLock {
        lock = try runLocks.acquire(run: temporary.url)
      }

      try files.createFile(
        manifestBytes,
        at: temporary.appending(StoreLayout.manifestFile).url,
      )
      try files.createFile(
        [],
        at: temporary.appending(StoreLayout.resultsFile).url,
      )

      if let stamp {
        try files.createFile(
          stamp,
          at: temporary.appending(StoreLayout.startFile).url,
        )
        try makeReportFolders(
          for: publication.reportFolders,
          in: temporary,
        )
      }

      try files.flushFolder(at: temporary.url)
      try files.publishFolder(
        temporary.url,
        as: runs.appending(identifier.text).url,
      )

      return lock
    } catch {
      lock?.release()
      files.discard(temporary.url)

      throw error
    }
  }

  /// `reports/<validation-id>/` for every selected validation (chapter 13 §5 step 5).
  private func makeReportFolders(
    for validations: [IdentifierSegment],
    in run: StoreFile,
  ) throws(StoreWritingError) {
    let reports = run.appending(StoreLayout.reportsFolder)
    try files.ensureFolder(at: reports.url)

    for validation in validations {
      try files.ensureFolder(at: reports.appending(validation.text).url)
    }
  }

  /// `start.json` as the run's folder will hold it, checked against its schema before anything is
  /// written.
  private func stampBytes(
    of draft: StartDraft?,
    for manifest: RunManifest,
    in folder: StoreFile,
  ) throws(StoreWritingError) -> [UInt8]? {
    guard let draft else {
      return nil
    }

    let stamp = StartStamp(
      identifier: manifest.identifier,
      startedAt: manifest.createdAt,
      openedBy: draft.openedBy,
      selected: draft.selected,
      validationsDigest: draft.validationsDigest,
      routes: draft.routes,
      files: draft.files,
    )
    let bytes = printer.pretty(stamp.document)

    _ = try validated(
      bytes,
      against: checks.start,
      location: folder.appending(StoreLayout.startFile).location,
    )

    return bytes
  }

  private func identifier(of number: RunNumber) throws(StoreWritingError) -> RunIdentifier {
    do {
      return try number.identifier()
    } catch {
      throw .identifiersExhausted
    }
  }
}
