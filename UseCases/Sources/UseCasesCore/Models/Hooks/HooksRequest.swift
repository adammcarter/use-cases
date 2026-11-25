import Foundation

/// What `hooks` was asked (chapter 18): to look, or to add or remove the hooks it names.
public struct HooksRequest: Equatable, Sendable {
  /// The workspace root.
  public let root: URL

  /// What to do; `nil` only looks.
  public let action: HookAction?

  /// The hooks to add or remove.
  public let names: [HookName]

  /// The full path of the `use-cases` that adds the hook, which the hook remembers for a shell
  /// that has no `use-cases` on its PATH (chapter 18 §3).
  public let program: String

  /// Makes the request.
  public init(
    root: URL,
    action: HookAction?,
    names: [HookName],
    program: String,
  ) {
    self.root = root
    self.action = action
    self.names = names
    self.program = program
  }
}
