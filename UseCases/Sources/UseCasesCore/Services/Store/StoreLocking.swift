import Foundation

/// Takes the exclusive lock that keeps run allocation unique across processes (chapter 12 §9).
protocol StoreLocking: Sendable {
  /// Runs `body` while holding an exclusive lock on `lock`, waiting for another holder first. The
  /// lock is released when `body` ends, however it ends, and when the process does.
  func locked<Value>(
    at lock: URL,
    perform body: () throws(StoreWritingError) -> Value,
  ) throws(StoreWritingError) -> Value
}
