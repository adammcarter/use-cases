import Foundation

/// Takes the lock of one run, which belongs to the process that finishes, aborts or seals it
/// (chapter 12 §18). A second process that wants the same run is refused, never made to wait.
protocol RunLocking: Sendable {
  /// Runs `body` while holding the exclusive lock of a run, and returns what it returns. When
  /// another process (or another holder in this one) holds the lock, returns `nil` at once and
  /// does not run `body`.
  ///
  /// The lock is released when `body` ends, and when the process dies: a lock that is free for a
  /// run that is not sealed is how a run that stopped is told from one that is being finished
  /// (chapter 12 §23).
  ///
  /// - Parameters:
  ///   - run: The run's folder; the lock file is made inside it.
  ///   - body: What to do with the lock held.
  func holding<Value>(
    run: URL,
    perform body: () async -> Value,
  ) async throws(StoreWritingError) -> Value?

  /// Takes the lock of a run whose folder is not published yet, and keeps it: the run is held
  /// from the moment it appears, so no other request can reach it first. The lock follows the
  /// folder through the rename that publishes it.
  ///
  /// - Parameter run: The folder, which has to be there.
  /// - Returns: The held lock, to be released when the request is done; `nil` when another holder
  ///   has it.
  func acquire(run: URL) throws(StoreWritingError) -> HeldRunLock?
}
