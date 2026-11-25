/// A file given as evidence, opened for reading: the name it is shown by and its bytes, to be
/// read once, a chunk at a time, as they are copied into the run.
struct AttachmentSource {
  /// The last name of the path it came from. Never a place on disk (chapter 12 §16).
  let name: String

  /// The bytes of the file, from its start.
  let chunks: any FileChunkReading
}
