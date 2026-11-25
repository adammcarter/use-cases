/// Something that decides which workspace paths a path pattern covers.
protocol PathPatternMatching: Sendable {
  /// Whether the pattern matches exactly this path.
  func matches(_ path: WorkspacePath) -> Bool

  /// Whether this path is excluded by the pattern: it matches, or a folder above it does.
  /// As in `.gitignore`, a pattern that matches a folder excludes everything in it. This is
  /// the rule for `discovery.exclude`, where a folder is never entered.
  func excludes(_ path: WorkspacePath) -> Bool
}
