import Foundation

/// Knows whether a change can be made where it is asked, before anything is written (chapter 16
/// §17).
protocol ChangeChecking: Sendable {
  /// Refuses a change that cannot be made where it is asked: a file to create that is there, a
  /// file to replace or delete that is not a file, a file where a folder is needed.
  func check(
    _ change: FileChange,
    in root: URL,
  ) throws(PlanWritingError)
}
