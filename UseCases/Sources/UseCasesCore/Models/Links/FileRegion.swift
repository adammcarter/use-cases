/// A marker region and the file it was found in.
struct FileRegion: Hashable, Sendable {
  let file: WorkspacePath
  let region: MarkerRegion
}
