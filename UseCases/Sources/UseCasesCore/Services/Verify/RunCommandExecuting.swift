/// Runs the command of one validation for `verify --run` (chapter 14).
protocol RunCommandExecuting: Sendable {
  /// Runs the validation's command in its working folder with `{report}` replaced, keeps what it
  /// printed in the run's `outputs/`, and says how it came out. A command that cannot be
  /// launched, that times out or that a signal kills is a ``RanCommand`` with a `failure`, not a
  /// thrown error. The console is kept for every command that started, a cancelled one included.
  ///
  /// - Parameters:
  ///   - validation: The validation to run.
  ///   - run: The run whose `{report}` the command writes, and whose `outputs/` hold its console.
  /// - Throws: ``VerifyError`` when the console cannot be stored.
  func execute(
    _ validation: BridgeValidation,
    in run: OpenRun,
  ) async throws(VerifyError) -> CommandExecution
}
