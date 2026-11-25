/// The folders listed so far while paths are looked up, so a folder is listed once.
struct FolderListings: Sendable {
  private var listed: [WorkspacePath: [FileEntry]] = [:]

  /// The entries of a folder, listed on the first ask.
  mutating func entries(
    in folder: WorkspacePath,
    context: DiscoveryContext,
    fileSystem: any FileSystemReading,
  ) throws(FileSystemError) -> [FileEntry] {
    if let known = listed[folder] {
      return known
    }

    let entries = try fileSystem.entries(in: context.url(for: folder))
    listed[folder] = entries

    return entries
  }
}
