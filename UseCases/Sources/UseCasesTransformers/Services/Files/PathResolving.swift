/// Paths of one workspace, spelled the way the contract spells them: relative to the code root,
/// with `/` separators.
protocol PathResolving: Sendable {
  /// The code root, absolute.
  var root: String { get }

  /// The workspace-relative spelling of `path` (absolute, or relative to the code root), or nil
  /// when it is missing or lies outside the workspace.
  func relativePath(of path: String?) -> String?

  /// `path` as an absolute path: itself when it is absolute, else inside `directory`, which is
  /// itself relative to the code root unless absolute.
  func resolve(
    _ path: String,
    in directory: String,
  ) -> String

  /// The absolute path of a workspace-relative `path`.
  func absolute(_ path: String) -> String
}
