/// The finish point of a verify run (chapter 13 §7): reads the run's reports, judges, applies the
/// guard and seals. `verify --finish` and `verify --run` share it.
protocol FinishPointing: Sendable {
  /// Finishes a run whose lock the caller holds.
  ///
  /// - Parameters:
  ///   - run: The open run.
  ///   - stamp: Its start stamp.
  ///   - resolved: The workspace as it is now, with its links.
  ///   - ran: What `verify --run` knows about the command it ran for each validation; empty when
  ///     the person's own tests wrote the reports.
  ///   - reloading: Reads the workspace again, for the guard.
  /// - Returns: The sealed run. A run error does not throw: it is sealed in the run.
  /// - Throws: ``VerifyError`` when the run cannot be read at all: the settings changed since the
  ///   start point, the workspace is INVALID, or the store cannot be written. The run stays open.
  func finish(
    _ run: OpenRun,
    stamp: StartStamp,
    in resolved: ResolvedWorkspace,
    ran: [IdentifierSegment: RanCommand],
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun

  /// Seals a `--run` whose commands were stopped by a cancellation as interrupted, with no
  /// verdicts and every selected source not processed (chapter 13 §15). The run's lock is held by
  /// the caller.
  ///
  /// - Parameters:
  ///   - run: The open run.
  ///   - planned: The validations the run reads, in the order of the bridge settings.
  ///   - ran: What each command that ended before the cancellation did.
  /// - Returns: The sealed run.
  /// - Throws: ``VerifyError`` when the store cannot be written. The run stays open.
  func interrupt(
    _ run: OpenRun,
    planned: [BridgeValidation],
    ran: [IdentifierSegment: RanCommand],
  ) throws(VerifyError) -> VerifiedRun
}
