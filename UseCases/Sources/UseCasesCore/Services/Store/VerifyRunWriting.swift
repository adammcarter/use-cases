import Foundation

/// Writes the runs of `verify` (chapter 12 §6, §11): a run that is opened with its start stamp
/// and its reports folders, taken up again by the request that finishes or aborts it, and given
/// its finalized manifest before it is sealed.
protocol VerifyRunWriting: RunWriting {
  /// Allocates a verify run and publishes it whole: its folder holds the initial manifest with
  /// the planned sources, an empty log, `start.json`, and an empty `reports/<validation-id>/`
  /// for every selected validation. All of it appears with the rename, so a crash never leaves
  /// a verify run without its start stamp (chapter 13 §5).
  ///
  /// - Parameters:
  ///   - draft: What the start point noted, and the sources the run plans to read.
  ///   - workspace: The workspace root, as discovery resolved it.
  func openVerifyRun(
    _ draft: StartDraft,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun

  /// As ``openVerifyRun(_:in:)``, and the run is held from the moment it is published, as
  /// ``RunWriting/openHeldRun(kind:in:)`` holds one (chapter 13 §7: the lock is taken before
  /// `start.json` exists).
  func openHeldVerifyRun(
    _ draft: StartDraft,
    in workspace: URL,
  ) throws(StoreWritingError) -> HeldRun

  /// Takes up a run that was opened earlier and is not sealed, with the manifest as it is on
  /// disk.
  func reopenRun(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun

  /// Replaces the run's initial manifest with the one that says what happened, once, before the
  /// run is sealed (chapter 12 §11). The manifest has to be the run's own.
  func finalize(
    _ manifest: RunManifest,
    of run: OpenRun,
  ) throws(StoreWritingError)

  /// Replaces the run's log with an empty one, once, before the run is sealed. An aborted run
  /// has no results: lines an unfinished finish staged, whole or torn, are never evidence
  /// (chapter 13 §6), and the log is one of the two files the core may replace before sealing
  /// (chapter 12 §1).
  func clearResults(of run: OpenRun) throws(StoreWritingError)

  /// Keeps what a run command printed as `outputs/<validation-id>/console.txt`, once, before the
  /// run is sealed (chapter 12 §15). Only the core writes `outputs/`.
  ///
  /// - Parameters:
  ///   - console: The bounded capture of the command's stdout and stderr, as text.
  ///   - validation: The validation whose command printed it.
  ///   - run: The run that is not sealed.
  func writeConsole(
    _ console: String,
    of validation: IdentifierSegment,
    in run: OpenRun,
  ) throws(StoreWritingError)
}
