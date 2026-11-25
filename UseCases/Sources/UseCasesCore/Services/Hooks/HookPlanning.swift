/// Plans what `hooks` does to a clone (chapter 18), writing nothing: `init --hooks` and
/// `hooks add` and `remove` plan the same way, so a preview is the real run without its write.
public protocol HookPlanning: Sendable {
  /// - Parameter request: The workspace, the action and the hooks it names.
  /// - Returns: The hooks as the request leaves them, the files to write and what to tell.
  /// - Throws: ``HooksError``: not a git repository, git cannot be run, or a hook cannot be read.
  func plan(_ request: HooksRequest) async throws(HooksError) -> HooksPlan
}
