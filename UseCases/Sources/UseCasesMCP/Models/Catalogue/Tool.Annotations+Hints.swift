import MCP

extension Tool.Annotations {
  /// Looks and changes nothing, and reaches nothing outside the workspace.
  static let readOnly = Tool.Annotations(
    readOnlyHint: true,
    openWorldHint: false,
  )

  /// Adds to the workspace's results and never removes or overwrites anything.
  static let additive = Tool.Annotations(
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: false,
  )

  /// Runs the project's own tests, which may reach beyond the workspace.
  static let runsTests = Tool.Annotations(
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: true,
  )

  /// Replaces or removes authored files; the same call again changes nothing more.
  static let rewritesFiles = Tool.Annotations(
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  )

  /// Records onto authored files and overwrites nothing; the same call again changes nothing
  /// more.
  static let recordsOnce = Tool.Annotations(
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false,
  )
}
