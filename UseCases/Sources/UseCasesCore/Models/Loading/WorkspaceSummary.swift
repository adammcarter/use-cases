/// What `validate` counts in a workspace that loaded (chapter 16 §8).
public struct WorkspaceSummary: Equatable, Sendable {
  /// Every use case, whether READY or DRAFT.
  public let useCases: Int

  /// The use cases that are fully written (chapter 02).
  public let ready: Int

  /// The use cases that are readable and incomplete.
  public let draft: Int

  /// The use case files that were read, relative to the workspace root, sorted by path.
  public let files: [String]
}
