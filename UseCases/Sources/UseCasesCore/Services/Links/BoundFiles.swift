/// What manual bindings have read so far, so a file several bindings point at is read once.
struct BoundFiles: Sendable {
  /// The folders listed on the way to the files.
  var listings = FolderListings()

  private var contents: [WorkspacePath: ManualContent] = [:]

  /// The file's content, when an earlier binding read it.
  func content(of file: WorkspacePath) -> ManualContent? {
    contents[file]
  }

  /// Keeps what a binding read.
  mutating func remember(
    _ content: ManualContent,
    of file: WorkspacePath,
  ) {
    contents[file] = content
  }
}
