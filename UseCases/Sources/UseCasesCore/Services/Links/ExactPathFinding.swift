/// Finds a path the workspace names, matching every name byte for byte (chapter 04 "Path
/// spelling").
protocol ExactPathFinding: Sendable {
  /// What stands at `path`. Every name on the way is found in a folder listing, so a file system
  /// that ignores case or Unicode form cannot make `Src/app.js` name `src/app.js`; a symlink on
  /// the way is not followed.
  ///
  /// - Returns: What the last name is: a file, a folder, a symlink or something else.
  func find(
    _ path: WorkspacePath,
    in context: DiscoveryContext,
    listings: inout FolderListings,
  ) throws(ExactPathError) -> FileEntryKind
}
