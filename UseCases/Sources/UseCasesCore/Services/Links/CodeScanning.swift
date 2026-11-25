/// Walks the code of a workspace and reads the marker regions out of every file (chapter 09
/// §20.3).
protocol CodeScanning: Sendable {
  /// Every well-paired marker region under the workspace root, and every problem met.
  ///
  /// The walk never leaves the root and never follows a symlink: a symlink is read as the text
  /// it points with. It does not enter what `context` excludes or a nested workspace, and it
  /// skips the files Use Cases owns. A file or folder it cannot read is a problem; a pipe,
  /// socket or device, and a name no path can spell, are warned about and skipped.
  func scan(
    _ workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> CodeScan
}
