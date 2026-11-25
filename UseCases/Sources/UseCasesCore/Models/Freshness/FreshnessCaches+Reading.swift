extension FreshnessCaches {
  /// The bytes of a file, read on the first ask and kept (chapter 11 §74). A file that is both
  /// linked and a resource, or named by several routes, is read once.
  mutating func bytes(
    of file: WorkspacePath,
    using reader: any FileContentReading,
    in context: DiscoveryContext,
  ) throws(FileContentError) -> [UInt8] {
    if let known = bytes[file] {
      return known
    }

    let read = try reader.bytes(
      of: file,
      in: context,
    )
    bytes[file] = read

    return read
  }
}
