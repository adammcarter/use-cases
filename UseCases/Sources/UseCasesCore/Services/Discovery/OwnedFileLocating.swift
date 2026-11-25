/// Finds a file Use Cases owns by its exact name, the same on every system: a file system that
/// ignores case would otherwise find `Use-Case-Groups.yml` on one machine and not on another.
protocol OwnedFileLocating: Sendable {
  /// - Parameters:
  ///   - name: The one name the file has.
  ///   - root: The checked workspace root, whose listing decides.
  ///   - scopes: Every scope of the workspace; the file is root-only, so one in any other is a
  ///     problem.
  ///   - belowRoot: The problem a file of this name in a child scope is, given its path.
  /// - Throws: ``FileSystemError`` when the root cannot be listed: nothing is said to be absent
  ///   that could not be looked at. A child scope that cannot be listed is not reported here: its
  ///   own files are read, and reported, elsewhere.
  func locate(
    _ name: String,
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
    belowRoot: (WorkspacePath) -> Diagnostic,
  ) throws(FileSystemError) -> OwnedFileLocation
}
