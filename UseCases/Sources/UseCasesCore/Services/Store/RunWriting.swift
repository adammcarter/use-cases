import Foundation

/// Writes runs into the results store of a workspace (chapter 12 §6 and §35). Only the core
/// writes the store.
protocol RunWriting: Sendable {
  /// Allocates the next run id and publishes the run: its folder holds the initial manifest and
  /// an empty log, and is renamed into place whole, so no one ever sees half of it.
  ///
  /// Allocation is unique across processes (chapter 12 §9). Nothing is written when the
  /// allocation metadata is malformed.
  ///
  /// - Parameters:
  ///   - kind: What produces the run's verdicts.
  ///   - workspace: The workspace root, as discovery resolved it.
  func openRun(
    kind: RunKind,
    in workspace: URL,
  ) throws(StoreWritingError) -> OpenRun

  /// As ``openRun(kind:in:)``, and the run is held from the moment it is published: its lock was
  /// taken in the folder before the rename that makes it a run, so nobody can seal or take up the
  /// run before the caller has it. The caller releases the lock when it is done with the run.
  func openHeldRun(
    kind: RunKind,
    in workspace: URL,
  ) throws(StoreWritingError) -> HeldRun

  /// Adds one result to the log of a run that is not sealed. It is durable, and it is not
  /// evidence until the run is sealed (chapter 12 §19).
  func append(
    _ result: StoredResult,
    to run: OpenRun,
  ) throws(StoreWritingError)

  /// Keeps files as evidence inside a run that is not sealed (chapter 12 §17): each file is
  /// copied, a chunk at a time, into the run, and published under the digest of its exact bytes;
  /// a file whose bytes are already there is not written again. Do this before appending the
  /// result that names them.
  ///
  /// - Returns: A descriptor for each file, in the order given. Its size is the number of bytes
  ///   that were copied.
  func ingest(
    _ sources: [AttachmentSource],
    into run: OpenRun,
  ) throws(StoreWritingError) -> [ResultAttachment]

  /// Seals the run: checks the manifest and every result, digests the files, and publishes
  /// `completion.json` without overwriting one. The run's results become visible together.
  ///
  /// - Parameters:
  ///   - run: The run to seal.
  ///   - termination: How the run ended.
  ///   - readReports: The digests of report files as a transformer read them (chapter 12 §15).
  ///     They are sealed in place of the digests of the same files now, so the sealed bytes are
  ///     the bytes the verdicts came from. Every other file under `reports/` is digested now.
  /// - Returns: The marker that was published.
  func seal(
    _ run: OpenRun,
    termination: RunTermination,
    readReports: [FileDigest],
  ) throws(StoreWritingError) -> RunCompletion
}

extension RunWriting {
  /// Seals a run whose reports, if it has any, are sealed as they are now.
  func seal(
    _ run: OpenRun,
    termination: RunTermination,
  ) throws(StoreWritingError) -> RunCompletion {
    try seal(
      run,
      termination: termination,
      readReports: [],
    )
  }
}
