@testable import UseCasesCore

/// The real start point, which does something of the test's between reading the code and writing
/// the run, and between writing and handing the run back.
struct MockRunOpener: RunOpening {
  let starter: VerifyStarter
  let afterPreparing: @Sendable () -> Void

  func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
    openedBy opener: RunOpener,
  ) throws(VerifyError) -> PreparedVerifyStart {
    let prepared = try starter.prepare(
      request,
      in: resolved,
      openedBy: opener,
    )
    afterPreparing()

    return prepared
  }

  func open(_ prepared: PreparedVerifyStart) throws(VerifyError) -> OpenedRun? {
    try starter.open(prepared)
  }
}
