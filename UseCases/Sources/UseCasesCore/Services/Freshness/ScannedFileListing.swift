/// Lists the files the code scan reads (chapter 09 §20.3), which is all a resource glob may
/// match (chapter 11 §42).
protocol ScannedFileListing: Sendable {
  /// Every file the scan of `workspace` would read, sorted by path, and every folder that could
  /// not be listed.
  ///
  /// It walks the way the scan does: it never leaves the root, never follows a symlink, does
  /// not enter what `context` excludes or a nested workspace, and leaves out the files Use Cases
  /// owns. It reads no file.
  func files(
    in workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> ScannedFiles
}
