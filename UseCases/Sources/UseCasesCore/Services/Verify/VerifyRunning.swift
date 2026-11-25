/// `use-cases verify --run` (chapter 13 §7): the start point, each selected validation's command,
/// and the finish point, in one request.
public protocol VerifyRunning: Sendable {
  /// Opens a run as `verify --start` does, with the run's lock held until the seal; runs each
  /// selected validation's command in the order of the bridge settings, with `{report}` pointing
  /// into the run, keeping what each printed; then finishes the run as `verify --finish` does,
  /// knowing each command's exit code (chapter 13 §7, chapter 14).
  ///
  /// A request cancelled by SIGINT or SIGTERM stops starting commands, stops the one that runs,
  /// and seals the run as interrupted with no verdicts (chapter 13 §15).
  ///
  /// A run error (a command that could not be launched, timed out or was killed, a missing report,
  /// a broken transformer) is sealed in the run, never thrown. With no validation to run, nothing
  /// is written (chapter 13 §13).
  ///
  /// - Parameters:
  ///   - request: What was asked.
  ///   - resolved: A workspace that loaded, and what link resolution found in it.
  ///   - reloading: Reads the workspace again after the reports were read, for the guard.
  /// - Throws: ``VerifyError`` when `--only` names an unknown validation, the workspace is INVALID,
  ///   the store cannot be written, or the request was cancelled before a run was opened. A run
  ///   that was opened and then could not be finished stays open for `--abort`.
  func run(
    _ request: VerifyRunRequest,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun
}
