/// Reads one validation's report where the tests wrote it (chapter 13 §7 step 3).
protocol SourceReading: Sendable {
  /// Digests the validation's reports folder, asks the validation's transformer for the results
  /// of the report in place, and digests the folder again. Whatever goes wrong with the source
  /// is the source's `error`, never a thrown error and never a verdict.
  ///
  /// - Parameters:
  ///   - validation: The validation to read.
  ///   - run: The run the report was written into.
  ///   - resolved: The workspace as it is at the finish point, with its links.
  ///   - ran: What `verify --run` knows about the command it ran; `nil` when the person's own
  ///     tests wrote the report.
  ///   - runner: Runs the transformer.
  func read(
    _ validation: BridgeValidation,
    run: OpenRun,
    in resolved: ResolvedWorkspace,
    ran: RanCommand?,
    using runner: any TransformerRunning,
  ) async -> SourceOutcome
}
