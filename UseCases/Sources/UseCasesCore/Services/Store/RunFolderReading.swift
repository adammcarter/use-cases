import Foundation

/// Reads one folder of `runs/`.
protocol RunFolderReading: Sendable {
  func readRun(
    _ identifier: RunIdentifier,
    in workspace: URL,
  ) -> RunOutcome
}
