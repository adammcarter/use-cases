import Foundation

/// Keeps attachments in the system's temporary folder.
struct AttachmentSpooler: AttachmentSpooling {
  private let files: any StoreFileWriting
  private let hasher: any Hashing

  /// - Parameters:
  ///   - files: How a copy is written.
  ///   - hasher: Makes the digests.
  init(
    files: any StoreFileWriting = LocalStoreFileWriter(),
    hasher: any Hashing = SHA256Hasher(),
  ) {
    self.files = files
    self.hasher = hasher
  }

  func spool(_ sources: [AttachmentSource]) throws(StoreWritingError) -> SpooledAttachments {
    guard !sources.isEmpty else {
      return .none
    }

    let folder = AttachmentSpoolFolder()
    var kept: [SpooledAttachment] = []

    // A failure part way lets go of the folder, which takes what was copied with it.
    try files.ensureFolder(at: folder.url)

    for source in sources {
      let copied = DigestingChunkReader(
        source.chunks,
        using: hasher,
      )
      let file = try files.stageFile(
        copying: copied,
        in: folder.url,
      )
      let found = copied.streamed

      kept.append(
        SpooledAttachment(
          name: source.name,
          file: file,
          digest: found.digest,
          length: found.length,
        ),
      )
    }

    return SpooledAttachments(
      folder: folder,
      files: kept,
    )
  }
}
