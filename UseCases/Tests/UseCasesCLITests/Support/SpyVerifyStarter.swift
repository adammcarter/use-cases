import UseCasesCore

/// The real start point, which does something of the test's after it has noted the code and after
/// it has written the run.
struct SpyVerifyStarter: VerifyStarting {
  let starter = VerifyStarter()
  let afterPreparing: @Sendable () -> Void
  let afterCommitting: @Sendable () -> Void

  func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
  ) throws(VerifyError) -> PreparedVerifyStart {
    let prepared = try starter.prepare(
      request,
      in: resolved,
    )
    afterPreparing()

    return prepared
  }

  func commit(_ prepared: PreparedVerifyStart) throws(VerifyError) -> StartedVerifyRun {
    let started = try starter.commit(prepared)
    afterCommitting()

    return started
  }
}
