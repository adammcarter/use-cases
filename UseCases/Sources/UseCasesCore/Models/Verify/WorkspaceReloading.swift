/// Reads the workspace again, as every request does when it begins (chapter 09): the finish point
/// reads it a second time after the reports were read, to see whether the code moved.
public protocol WorkspaceReloading: Sendable {
  /// The workspace as it is now, with its links.
  ///
  /// - Throws: ``ReloadingError`` when the workspace is INVALID now, or the request was cancelled.
  func reload() async throws(ReloadingError) -> ResolvedWorkspace
}
