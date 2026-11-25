/// Reduces content to a reference (chapter 11 §8, §89.3).
protocol ContentReferencing: Sendable {
  /// The reference of bytes after normalization.
  func reference(of bytes: [UInt8]) -> ContentReference

  /// The reference of a file after normalization, and the SHA-256 of its exact bytes, found by
  /// reading it a chunk at a time: the reference is the one ``reference(of:)`` gives for the
  /// bytes of the file at once.
  ///
  /// A file is read once when normalization leaves it as it is, which is nearly always, and
  /// twice when it does not, the length of the normalized content being needed before the first
  /// byte of it is hashed.
  ///
  /// - Parameter open: Opens the file; called again for a second reading.
  /// - Throws: ``FileContentError/changedWhileRead`` when the second reading is not of the bytes
  ///   the first one was.
  func reference(
    streaming open: () throws(FileContentError) -> any FileChunkReading,
  ) throws(FileContentError) -> StreamedContent

  /// The reference of the pieces of `bytes` at `ranges`, joined in the order given.
  func reference(
    of bytes: [UInt8],
    ranges: [Range<Int>],
  ) throws(FingerprintingError) -> ContentReference
}
