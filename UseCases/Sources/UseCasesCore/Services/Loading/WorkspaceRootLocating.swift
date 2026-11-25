import Foundation

/// Names the workspace root without loading the workspace (chapter 16 §3), for a request that
/// needs only the results store: `verify --abort` (chapter 13 §6).
public protocol WorkspaceRootLocating: Sendable {
  /// The canonical root folder, found the way a load finds it: by walking up from a folder, or
  /// the folder named, which has to be the root. Reads only the `use-cases.yml` files that decide
  /// the root; no use case, link or bridge setting is read, so none can keep this from answering.
  ///
  /// - Parameter start: Where to begin looking.
  /// - Throws: ``WorkspaceLoadingError`` when no root can be named.
  func locateRoot(from start: WorkspaceStart) throws(WorkspaceLoadingError) -> URL
}
