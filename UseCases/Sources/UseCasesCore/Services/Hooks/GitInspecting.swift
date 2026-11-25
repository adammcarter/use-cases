import Foundation

/// Finds where a clone keeps its hooks (chapter 18 §3).
public protocol GitInspecting: Sendable {
  /// - Parameter folder: A folder in the clone, such as the workspace root.
  /// - Returns: The top of the work tree, the hooks folder and whether a hook manager owns it.
  /// - Throws: ``HooksError``: the folder is not in a git repository, or git cannot be run.
  func locate(from folder: URL) async throws(HooksError) -> GitLocation
}
