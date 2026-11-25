import Foundation

extension WorkspaceRoot {
  /// Where a workspace path is on disk.
  func location(of path: WorkspacePath) -> URL {
    guard !path.isRoot else {
      return directory
    }

    return directory.appendingPathComponent(path.text)
  }
}
