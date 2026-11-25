/// The start point of a verify run, for the request that goes on to run the commands itself
/// (chapter 13 §7).
protocol RunOpening: Sendable {
  /// Does what ``VerifyStarting/prepare(_:in:)`` does for the run that `opener` opens.
  func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
    openedBy opener: RunOpener,
  ) throws(VerifyError) -> PreparedVerifyStart

  /// Publishes the run as ``VerifyStarting/commit(_:)`` does, and returns it held: its lock was
  /// taken before the run could be seen (chapter 13 §7), and the caller releases it.
  ///
  /// - Returns: The run; `nil` when no validation is selected and no run is written.
  func open(_ prepared: PreparedVerifyStart) throws(VerifyError) -> OpenedRun?
}
