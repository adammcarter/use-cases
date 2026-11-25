extension FinishPoint {
  /// The validations the start point selected, as the bridge settings have them now. They have to
  /// be exactly those `start.json` recorded: a different report name or transformer would read
  /// the wrong files (chapter 13 §7 step 1).
  func selectedValidations(
    of stamp: StartStamp,
    in workspace: LoadedWorkspace,
  ) throws(VerifyError) -> [BridgeValidation] {
    // In the order of the file, as the start point noted them: a validation that was removed, or
    // moved, is not the validation the reports were made for (chapter 13 §7 step 1).
    let selected = (workspace.bridge?.validations ?? []).filter { validation in
      stamp.selected.contains(validation.identifier)
    }

    guard
      selected.map(\.identifier) == stamp.selected,
      digester.digest(of: selected) == stamp.validationsDigest
    else {
      throw .settingsChanged(run: stamp.identifier.text)
    }

    return selected
  }

  /// A finish that stopped partway may have left results in the log; a second finish would
  /// repeat them and the seal would find the log corrupt.
  func requireNoStagedResults(in run: OpenRun) throws(VerifyError) {
    let results = store.folder(
      of: run.identifier,
      in: run.workspace,
    ).appending(StoreLayout.resultsFile)

    do {
      guard try !store.access.requiredBytes(of: results).isEmpty else {
        return
      }
    } catch {
      throw .storage(error.description)
    }

    throw .stagedResults(run: run.identifier.text)
  }

  /// Reads the validations one after another, in the order of the bridge settings, until the
  /// request is cancelled.
  func read(
    _ validations: [BridgeValidation],
    into run: OpenRun,
    in resolved: ResolvedWorkspace,
    ran: [IdentifierSegment: RanCommand],
  ) async -> Reading {
    let runner = makeRunner(cancellation)
    var outcomes: [SourceOutcome] = []
    var isCancelled = false

    for validation in validations {
      let outcome = await sources.read(
        validation,
        run: run,
        in: resolved,
        ran: ran[validation.identifier],
        using: runner,
      )

      outcomes.append(outcome)

      if outcome.isCancelled {
        isCancelled = true
        break
      }
    }

    // A signal that came after the last report was read is still a cancellation.
    let late = await cancellation.isCancelled()

    isCancelled = isCancelled || late

    return Reading(
      outcomes: outcomes,
      isCancelled: isCancelled,
    )
  }
}
