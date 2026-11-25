/// Reads the bytes a link or a resource is made of, the way the code scan reads them (chapter 11
/// §42).
protocol FileContentReading: Sendable {
  /// The bytes of the file at `file`. A symlink is never followed: its content is the text it
  /// points with.
  func bytes(
    of file: WorkspacePath,
    in context: DiscoveryContext,
  ) throws(FileContentError) -> [UInt8]

  /// The same content as ``bytes(of:in:)``, to be read a chunk at a time, for a file that is only
  /// hashed. A symlink is never followed: its content is the text it points with.
  func chunks(
    of file: WorkspacePath,
    in context: DiscoveryContext,
  ) throws(FileContentError) -> any FileChunkReading
}
