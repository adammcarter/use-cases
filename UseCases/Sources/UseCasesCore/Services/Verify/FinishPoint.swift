/// The finish point (chapter 13 §7). It reads each selected validation's report in place, judges
/// every READY route from the merged results, withholds the verdict of a route whose code changed
/// since the start point, and seals the run with the reports as they were read.
struct FinishPoint: FinishPointing {
  let store: VerifyStore
  let sources: any SourceReading
  let judge: any RouteJudging
  let digester: any ValidationsDigesting
  let fingerprinter: any RouteFingerprintComputing
  let makeRunner: @Sendable (any CancellationObserving) -> any TransformerRunning
  let cancellation: any CancellationScoping
  let clock: any Timekeeping

  func finish(
    _ run: OpenRun,
    stamp: StartStamp,
    in resolved: ResolvedWorkspace,
    ran: [IdentifierSegment: RanCommand],
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun {
    // The signals are held to the seal, so that one that comes between two of the steps is seen
    // by the next, down to the one just before the run is sealed.
    await cancellation.begin()

    let outcome: Result<VerifiedRun, VerifyError>

    do throws(VerifyError) {
      outcome = try await .success(
        finished(
          run,
          stamp: stamp,
          in: resolved,
          ran: ran,
          reloading: reloading,
        ),
      )
    } catch {
      outcome = .failure(error)
    }

    await cancellation.end()

    return try outcome.get()
  }

  private func finished(
    _ run: OpenRun,
    stamp: StartStamp,
    in resolved: ResolvedWorkspace,
    ran: [IdentifierSegment: RanCommand],
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun {
    let validations = try selectedValidations(
      of: stamp,
      in: resolved.workspace,
    )

    try requireNoStagedResults(in: run)

    let reading = await read(
      validations,
      into: run,
      in: resolved,
      ran: ran,
    )

    guard !reading.isCancelled else {
      return try sealInterrupted(
        run,
        reading: reading,
        planned: validations,
      )
    }

    let guarded: RouteFingerprints

    do {
      guarded = try await reloaded(reloading)
    } catch {
      // Cancelled before judging: the reports were read and nothing is judged (chapter 13 §15).
      guard error == .cancelled else {
        throw error
      }

      return try sealInterrupted(
        run,
        reading: reading,
        planned: validations,
      )
    }

    return try await seal(
      run,
      judged: judged(
        reading.outcomes,
        stamp: stamp,
        resolved: resolved,
        guarded: guarded,
      ),
      outcomes: reading.outcomes,
    )
  }

  /// The fingerprints of the workspace read again. A workspace that is INVALID now stops the
  /// finish and leaves the run open; a cancellation is thrown for the caller to seal.
  private func reloaded(_ reloading: any WorkspaceReloading) async throws(VerifyError)
    -> RouteFingerprints
  {
    let reloaded: ResolvedWorkspace

    do {
      reloaded = try await reloading.reload()
    } catch {
      switch error {
      case let .invalid(problems):
        throw .invalidWorkspace(problems: problems)
      case .cancelled:
        throw .cancelled
      }
    }

    let fingerprints = fingerprinter.fingerprints(
      of: reloaded.workspace,
      links: reloaded.links,
    )

    guard !fingerprints.isInvalid else {
      throw .invalidWorkspace(problems: fingerprints.problems)
    }

    return fingerprints
  }
}
