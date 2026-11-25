/// `use-cases verify --finish` (chapter 13 §6, §7): reads the reports a started run's tests wrote
/// and seals the run.
public protocol VerifyFinishing: Sendable {
  /// Chooses the run, takes its lock, reads the reports in place with the validations'
  /// transformers, judges every READY route, withholds the verdicts of routes whose code changed
  /// since the start point, and seals the run (chapter 13 §7).
  ///
  /// Only runs `verify --start` opened are chosen. The run is the one named, or the only one
  /// open. With no run open and no validations in the bridge settings, nothing is read and no run
  /// is written (chapter 13 §13).
  ///
  /// A run error (a missing report, a broken transformer) is sealed in the run, never thrown.
  ///
  /// - Parameters:
  ///   - request: What was asked.
  ///   - resolved: A workspace that loaded, and what link resolution found in it.
  ///   - reloading: Reads the workspace again after the reports were read, for the guard.
  /// - Throws: ``VerifyError`` when there is no run to finish, another process is finishing it,
  ///   the bridge settings changed since `--start`, the workspace is INVALID, or the store cannot
  ///   be written. The run stays open.
  func finish(
    _ request: VerifyFinishRequest,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun
}
