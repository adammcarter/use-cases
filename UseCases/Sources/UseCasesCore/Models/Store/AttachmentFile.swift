/// A file given as evidence that is held whole: the name it is shown by and its exact bytes, for
/// what is small. A file as big as a person made it is read a chunk at a time.
struct AttachmentFile: Equatable, Sendable {
  /// The last name of the path it came from. Never a place on disk (chapter 12 §16).
  let name: String

  let bytes: [UInt8]
}
