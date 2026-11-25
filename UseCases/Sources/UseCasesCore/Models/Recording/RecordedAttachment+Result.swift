extension RecordedAttachment {
  init(_ attachment: ResultAttachment) {
    self.init(
      name: attachment.name,
      blob: attachment.blob,
      sizeBytes: attachment.sizeBytes,
      mediaType: attachment.mediaType,
    )
  }
}
