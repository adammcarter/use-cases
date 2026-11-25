import Foundation

/// Says whether a folder is there, so that `use-cases mcp --workspace` can be refused at its start
/// and not by every call.
protocol FolderChecking: Sendable {
  /// Whether `folder` exists and is a folder.
  func isFolder(_ folder: URL) -> Bool
}
