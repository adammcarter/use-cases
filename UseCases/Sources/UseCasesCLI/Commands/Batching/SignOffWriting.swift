/// Checks and writes the change of `apply` and `approve`, and answers with it.
protocol SignOffWriting: Sendable {
  /// Checks the change as the workspace would be after it and, unless `dryRun`, writes it.
  ///
  /// - Parameters:
  ///   - change: The files the command changes, and how the workspace they leave is checked.
  ///   - command: `apply` or `approve`.
  ///   - global: The options every command takes.
  ///   - dryRun: Stop after the check.
  ///   - report: The answer, given what there is to say besides it: a cancellation that came
  ///     too late.
  func answer(
    _ change: PlannedSignOff,
    command: String,
    global: GlobalOptions,
    dryRun: Bool,
    report: ([String]) -> any WriteReporting,
  ) async -> CommandResult
}
