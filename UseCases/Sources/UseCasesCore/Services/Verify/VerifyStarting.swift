/// `use-cases verify --start` (chapter 13 §5): notes the code and opens a run for the tests to
/// write their reports into. The work is in two parts, so that a request cancelled while the code
/// is being noted writes nothing: ``prepare(_:in:)`` reads, ``commit(_:)`` writes.
public protocol VerifyStarting: Sendable {
  /// Selects the validations and notes every route's fingerprint and the digest of every linked
  /// and resource file. Writes nothing and touches no run.
  ///
  /// - Parameters:
  ///   - request: What was asked.
  ///   - resolved: A workspace that loaded, and what link resolution found in it.
  /// - Throws: ``VerifyError`` when `--only` names a validation the settings do not have, the
  ///   workspace is INVALID, or the store's runs cannot be listed.
  func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
  ) throws(VerifyError) -> PreparedVerifyStart

  /// Opens the run: its folder holds `start.json` and an empty reports folder for each selected
  /// validation, all published together. Runs nothing, judges nothing and touches no other run.
  ///
  /// With no validations in the bridge settings nothing is started and no run is written
  /// (chapter 13 §13).
  ///
  /// - Throws: ``VerifyError`` when the store cannot be written; no run is allocated.
  func commit(_ prepared: PreparedVerifyStart) throws(VerifyError) -> StartedVerifyRun
}

public extension VerifyStarting {
  /// Notes the code and opens the run in one go.
  func start(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
  ) throws(VerifyError) -> StartedVerifyRun {
    try commit(
      prepare(
        request,
        in: resolved,
      ),
    )
  }
}
