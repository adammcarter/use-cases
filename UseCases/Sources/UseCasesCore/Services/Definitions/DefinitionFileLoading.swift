import Foundation

/// Reads one definition file from disk into its use cases (chapter 09 §13 steps 1 to 8).
protocol DefinitionFileLoading: Sendable {
  /// The file's use cases in the order written, or every problem found in it.
  ///
  /// - Parameters:
  ///   - location: Where the file is on disk.
  ///   - path: The file, workspace-relative; every problem names it.
  func load(
    at location: URL,
    path: WorkspacePath,
  ) throws(DefinitionFileLoadingError) -> DefinitionFile
}
