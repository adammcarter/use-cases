import Foundation

/// Finds the runs that are open: no completion marker (chapter 12 §6, §22).
protocol OpenRunFinding: Sendable {
  /// Every unsealed run, in ascending run id: the verify runs that can be read, the ones whose
  /// start stamp is missing or cannot be read, which are never left out, and apart from them the
  /// record runs, which have no start stamp.
  ///
  /// - Parameter workspace: The workspace root, as discovery resolved it.
  func openRuns(in workspace: URL) throws(StoreProblem) -> OpenRuns

  /// What the store holds for one run id.
  func find(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) throws(StoreProblem) -> FoundRun
}
