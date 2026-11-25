/// Decides which files the code scan reads (chapter 09 §20.3), once, for everything that needs
/// the same set: the scan itself and the resource globs (chapter 11 §42).
protocol CodeFileWalking: Sendable {
  /// Every file under the workspace root that the scan reads, and every problem met.
  ///
  /// The walk never leaves the root and never follows a symlink. It does not enter what
  /// `context` excludes or a nested workspace, and it leaves out the files Use Cases owns. It
  /// reads no file. A folder it cannot list is a problem; a pipe, socket or device, and a name
  /// no path can spell, are warned about and skipped.
  func walk(
    _ workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> CodeWalk
}
