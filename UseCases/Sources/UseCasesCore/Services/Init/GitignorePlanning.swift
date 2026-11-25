import Foundation

/// Plans the `.use-cases/` line of `.gitignore` (chapter 17 §6).
protocol GitignorePlanning: Sendable {
  /// What to do about `.gitignore` in the workspace at `root`.
  func plan(for root: URL) throws(InitError) -> GitignorePlanner.Plan
}
