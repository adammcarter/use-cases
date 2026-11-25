/// Every file a command would create, replace or delete, in the order it would do it, and
/// nothing written (`docs/architecture.md` §2). One shared writer
/// checks the plan on a copy of the workspace and applies it; `--dry-run` stops before applying.
public struct WritePlan: Equatable, Sendable {
  /// The changes, in the order they are applied.
  public let changes: [FileChange]

  /// Whether there is nothing to write.
  public var isEmpty: Bool {
    changes.isEmpty
  }
}
