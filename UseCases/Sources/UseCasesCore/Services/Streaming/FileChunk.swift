/// How much of a file is held at a time when it is hashed or copied: no file is ever read whole
/// for either.
enum FileChunk {
  /// The most bytes a chunk holds.
  static let size = 1 << 16
}
