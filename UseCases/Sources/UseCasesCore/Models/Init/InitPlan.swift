import Foundation

/// What `init` would do, and nothing yet written (chapter 17). The plan of file writes is
/// checked on a copy of the workspace and applied by the shared writer; the rest is what the
/// command tells the person.
public struct InitPlan: Equatable, Sendable {
  /// The canonical folder that is set up.
  public let root: URL

  /// The folder is already a workspace root, whose kind and prefix are set: `init` adds to it and
  /// has nothing to ask about them.
  public let isExistingWorkspace: Bool

  /// The files to write, in the order they are written: the files that are made first, then
  /// the `.gitignore` line.
  public let writes: WritePlan

  /// The files `init` makes, in the order of chapter 17 §8, `.gitignore` not among them.
  public let created: [String]

  /// The files that were already there and are left exactly as they are.
  public let kept: [String]

  public let gitignore: GitignoreOutcome

  /// What the person is told besides: where `.use-cases/` has to be excluded when `init` could
  /// not do it.
  public let notes: [String]
}
