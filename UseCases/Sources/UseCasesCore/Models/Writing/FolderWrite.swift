import Foundation

/// A plan for a folder that is not the workspace, such as the hooks of a git clone: it is
/// applied there as it is, and the workspace's check does not cover it.
public struct FolderWrite: Equatable, Sendable {
  /// The folder the plan's paths are relative to.
  public let folder: URL

  public let plan: WritePlan

  /// Makes the plan for a folder.
  public init(
    folder: URL,
    plan: WritePlan,
  ) {
    self.folder = folder
    self.plan = plan
  }
}
