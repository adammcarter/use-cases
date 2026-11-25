/// What a request on the hooks comes to, and nothing yet written (chapter 18). The hooks are the
/// ones the clone will have once the writes are made, so a preview reads as the real run does.
public struct HooksPlan: Equatable, Sendable {
  /// The hooks folder, relative to the workspace root.
  public let hooksFolder: String

  /// `core.hooksPath` is set.
  public let isManaged: Bool

  /// Every hook, in the fixed order.
  public let hooks: [HookStatus]

  /// The hooks this request adds or removes, in the fixed order.
  public let changed: [HookName]

  /// What the person is told: the line to add to a hook that is not ours, or to a hook manager.
  public let notes: [String]

  /// A hook was left alone, which needs the person (chapter 18 §6).
  public let needsAttention: Bool

  /// The files to write, under the folder above the hooks folder.
  public let writes: FolderWrite
}
