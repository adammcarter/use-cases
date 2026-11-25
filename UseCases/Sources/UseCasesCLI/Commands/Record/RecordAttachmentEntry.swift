import UseCasesCore

/// One file kept with the verdict, in the shape of the result's `attachments` (chapter 12 §16).
struct RecordAttachmentEntry: Encodable {
  let name: String
  let blob: String
  let sizeBytes: Int

  /// Absent when the file name's ending is not in the table, never `null`.
  let mediaType: String?

  enum CodingKeys: String, CodingKey {
    case name
    case blob
    case sizeBytes = "size_bytes"
    case mediaType = "media_type"
  }

  init(_ attachment: RecordedAttachment) {
    name = attachment.name
    blob = attachment.blob
    sizeBytes = attachment.sizeBytes
    mediaType = attachment.mediaType
  }
}
