/// A file kept with a recorded verdict, as the result describes it (chapter 12 §16).
public struct RecordedAttachment: Equatable, Sendable {
  /// The display name: the last name of the path the file was given by.
  public let name: String

  /// The blob id: `uc-blob-v1-sha256:` and the digest of the exact bytes.
  public let blob: String

  /// The number of bytes.
  public let sizeBytes: Int

  /// The media type its file name's ending has in the fixed table, when it has one.
  public let mediaType: String?

  /// Makes the description of a kept file.
  public init(
    name: String,
    blob: String,
    sizeBytes: Int,
    mediaType: String?,
  ) {
    self.name = name
    self.blob = blob
    self.sizeBytes = sizeBytes
    self.mediaType = mediaType
  }
}
