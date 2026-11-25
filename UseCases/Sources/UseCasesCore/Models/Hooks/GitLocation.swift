import Foundation

/// Where a clone keeps its hooks (chapter 18 §3).
public struct GitLocation: Equatable, Sendable {
  /// The top of the git work tree, where git runs a hook: a canonical folder.
  public let workTree: URL

  /// The folder of this clone's hooks (`git rev-parse --git-path hooks`), canonical, whether or
  /// not it exists yet.
  public let hooksFolder: URL

  /// `core.hooksPath` is set: a hook manager owns every hook.
  public let isManaged: Bool

  /// Says where the hooks are.
  public init(
    workTree: URL,
    hooksFolder: URL,
    isManaged: Bool,
  ) {
    self.workTree = workTree
    self.hooksFolder = hooksFolder
    self.isManaged = isManaged
  }
}
