extension RunSource {
  /// The source a run keeps for a validation once something is known of it: the command that
  /// ran, when `verify --run` ran one, and why the source gave no results, if it did not.
  static func recorded(
    for validation: BridgeValidation,
    ran: RanCommand?,
    error: String? = nil,
    diagnostics: [String] = [],
  ) -> RunSource {
    let planned = RunSource.planned(for: validation)

    return RunSource(
      identifier: planned.identifier,
      report: planned.report,
      transformer: planned.transformer,
      workingDirectory: planned.workingDirectory,
      command: ran?.command,
      exitCode: ran?.exitCode.map(Int.init),
      seconds: ran?.seconds,
      error: error,
      diagnostics: diagnostics,
    )
  }
}
