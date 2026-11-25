extension VerifyRunner {
  /// Opens the run, holds its lock and runs it. Everything that can go wrong comes back as a
  /// result, so that the signals and the lock are always given back.
  func opened(
    _ request: VerifyRunRequest,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
    store: VerifyStore,
    finishing: any FinishPointing,
  ) async -> Result<VerifiedRun, VerifyError> {
    // A request cancelled before it began has opened nothing.
    guard await !cancellation.isCancelled() else {
      return .failure(.cancelled)
    }

    let opened: OpenedRun

    do throws(VerifyError) {
      let prepared = try opener.prepare(
        VerifyStartRequest(only: request.only),
        in: resolved,
        openedBy: .run,
      )

      // The code is noted: a cancellation that came meanwhile writes nothing (chapter 13 §15).
      if !prepared.writesNothing {
        guard await cancellation.claimWrite() else {
          return .failure(.cancelled)
        }
      }

      guard let found = try opener.open(prepared) else {
        return .success(VerifiedRun(nothingToReadNotes: [VerifyFinisher.nothingToRead]))
      }

      opened = found
    } catch {
      return .failure(error)
    }

    // The lock was taken before the run could be seen, so nobody has had it since.
    let outcome = await running(
      opened,
      in: resolved,
      reloading: reloading,
      store: store,
      finishing: finishing,
    )
    opened.lock.release()

    return outcome
  }
}
