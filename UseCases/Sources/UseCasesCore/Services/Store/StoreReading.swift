import Foundation

/// Reads the results store of a workspace: `<root>/.use-cases/` (chapter 12 §36).
protocol StoreReading: Sendable {
  /// Every sealed run, with the lookups status makes over them. A missing or empty store is a
  /// valid empty history. A run with no completion marker is listed and never counts.
  ///
  /// - Parameter workspace: The workspace root, as discovery resolved it.
  func readHistory(in workspace: URL) throws(StoreReadingError) -> StoreHistory
}
