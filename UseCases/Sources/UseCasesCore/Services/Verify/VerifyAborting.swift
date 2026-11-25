import Foundation

/// `use-cases verify --abort` (chapter 13 §6): closes a run nobody will finish.
public protocol VerifyAborting: Sendable {
  /// Seals an open run as interrupted, with no results and the note "aborted": result lines an
  /// unfinished finish staged, whole or torn, are dropped. The run's reports stay in its folder.
  /// Without a run id it closes the only open run, whichever request opened it; a run another
  /// process holds the lock of is refused, never waited for.
  ///
  /// It needs only the results store: no use case, link or bridge setting is read, so a
  /// workspace that does not load never keeps a run open (chapter 13 §6). A run whose own files
  /// are damaged is refused by name, unless `--run-id` names it and it can still be sealed.
  ///
  /// - Parameters:
  ///   - request: What was asked.
  ///   - root: The workspace root, named without loading the workspace.
  /// - Throws: ``VerifyError`` when there is no such open run, several are open and none is
  ///   named, another process is finishing the run, or the store cannot be written.
  func abort(
    _ request: VerifyAbortRequest,
    in root: URL,
  ) async throws(VerifyError) -> AbortedVerifyRun
}
