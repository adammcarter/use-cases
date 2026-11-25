extension FinishPoint {
  /// The run errors of the sources, then one for each entry under `reports/` that is not a
  /// regular file and that no source already named. They are found before the manifest is
  /// finalized, so that sealing, which digests `reports/`, never meets something it must refuse:
  /// what the tests wrote is never followed and never makes a run unsealable.
  func runErrors(
    of outcomes: [SourceOutcome],
    in run: OpenRun,
  ) -> [String] {
    let known = outcomes.compactMap(\.runError)
    let found = ReportDigester(access: store.access).unusableEntries(
      below: store.folder(
        of: run.identifier,
        in: run.workspace,
      ).appending(StoreLayout.reportsFolder),
    )

    return known + found.map(\.runError).filter { error in
      !known.contains(error)
    }
  }

  /// Appends every verdict in one burst, finalizes the manifest and seals the run, with the lock
  /// still held (chapter 13 §7 step 7). A cancellation that comes before the manifest is
  /// finalized, the last look before the seal, seals the run as interrupted with the verdicts
  /// already appended kept (chapter 13 §15); one that comes after is too late to stop the seal.
  func seal(
    _ run: OpenRun,
    judged: Judged,
    outcomes: [SourceOutcome],
  ) async throws(VerifyError) -> VerifiedRun {
    do {
      for result in judged.results {
        try store.writer.append(
          result,
          to: run,
        )
      }
    } catch {
      throw .storage(error.description)
    }

    let isCancelled = await cancellation.isCancelled()
    let manifest = RunManifest(
      identifier: run.identifier,
      createdAt: run.manifest.createdAt,
      kind: .verify,
      sources: outcomes.map(\.source),
      errors: runErrors(
        of: outcomes,
        in: run,
      ),
      diagnostics: judged.diagnostics,
      unlinkedTests: outcomes.flatMap(\.unlinked),
      notes: isCancelled ? [Self.cancelledAfterJudging] : [],
    )

    do {
      try store.writer.finalize(
        manifest,
        of: run,
      )
      _ = try store.writer.seal(
        run,
        termination: isCancelled ? .interrupted : .completed,
        readReports: outcomes.flatMap(\.readReports),
      )
    } catch {
      throw .storage(error.description)
    }

    return VerifiedRun(
      manifest: manifest,
      results: judged.results,
      isCancelled: isCancelled,
    )
  }

  /// What the manifest of a run cancelled after judging says.
  static let cancelledAfterJudging =
    "cancelled after judging; the verdicts already appended are kept"

  /// Seals a cancelled finish as interrupted: no verdicts, and the note says which sources were
  /// not processed (chapter 13 §15).
  func sealInterrupted(
    _ run: OpenRun,
    reading: Reading,
    planned: [BridgeValidation],
  ) throws(VerifyError) -> VerifiedRun {
    let done = reading.outcomes.filter { !$0.isCancelled }
    let finished = Set(done.map(\.identifier))

    return try sealInterrupted(
      run,
      sources: planned.map { validation in
        done.first { $0.identifier == validation.identifier }?.source
          ?? RunSource.planned(for: validation)
      },
      errors: runErrors(
        of: done,
        in: run,
      ),
      notProcessed: planned.map(\.identifier).filter { identifier in
        !finished.contains(identifier)
      },
      readReports: done.flatMap(\.readReports),
    )
  }

  /// Seals a `--run` cancelled while its commands ran as interrupted: no report was read, so every
  /// selected source was not processed. A command that ended before the signal keeps its own
  /// result in its source (chapter 13 §15, chapter 14 §14).
  func interrupt(
    _ run: OpenRun,
    planned: [BridgeValidation],
    ran: [IdentifierSegment: RanCommand],
  ) throws(VerifyError) -> VerifiedRun {
    let outcomes = planned.map { validation in
      let command = ran[validation.identifier]

      return SourceOutcome(
        source: RunSource.recorded(
          for: validation,
          ran: command,
          error: command?.failure,
        ),
        results: [],
        unlinked: [],
        readReports: [],
        isCancelled: false,
      )
    }

    return try sealInterrupted(
      run,
      sources: outcomes.map(\.source),
      errors: runErrors(
        of: outcomes,
        in: run,
      ),
      notProcessed: planned.map(\.identifier),
      readReports: [],
    )
  }

  private func sealInterrupted(
    _ run: OpenRun,
    sources: [RunSource],
    errors: [String],
    notProcessed: [IdentifierSegment],
    readReports: [FileDigest],
  ) throws(VerifyError) -> VerifiedRun {
    let note = notProcessed.isEmpty
      ? "cancelled before judging"
      : "cancelled before judging; sources not processed: "
      + notProcessed.map(\.text).joined(separator: ", ")

    let manifest = RunManifest(
      identifier: run.identifier,
      createdAt: run.manifest.createdAt,
      kind: .verify,
      sources: sources,
      errors: errors,
      diagnostics: [],
      unlinkedTests: [],
      notes: [note],
    )

    do {
      try store.writer.finalize(
        manifest,
        of: run,
      )
      _ = try store.writer.seal(
        run,
        termination: .interrupted,
        readReports: readReports,
      )
    } catch {
      throw .storage(error.description)
    }

    return VerifiedRun(
      manifest: manifest,
      results: [],
      isCancelled: true,
    )
  }
}
