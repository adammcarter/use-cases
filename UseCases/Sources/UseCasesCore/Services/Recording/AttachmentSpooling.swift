/// Keeps the attachments of a request as they are when it is checked, so that the verdict
/// committed later holds what was checked and not what the files have become (chapter 13 §12).
protocol AttachmentSpooling: Sendable {
  /// Copies every source, a chunk at a time, into a folder of its own, hashing and measuring it as
  /// it goes. Nothing is left behind when a copy fails.
  func spool(_ sources: [AttachmentSource]) throws(StoreWritingError) -> SpooledAttachments
}
