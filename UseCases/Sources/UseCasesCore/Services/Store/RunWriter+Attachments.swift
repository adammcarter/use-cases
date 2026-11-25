import Foundation

extension RunWriter {
  func ingest(
    _ sources: [AttachmentSource],
    into run: OpenRun,
  ) throws(StoreWritingError) -> [ResultAttachment] {
    // A run with no attachments has no `attachments/` folder.
    guard !sources.isEmpty else {
      return []
    }

    try requireUnsealed(
      run.identifier,
      in: run.workspace,
    )

    let root = folder(
      of: run.identifier,
      in: run.workspace,
    )
    let attachments = root.appending(StoreLayout.attachmentsFolder)
    var descriptors: [ResultAttachment] = []

    try files.ensureFolder(at: attachments.url)

    for source in sources {
      // The copy is hashed and measured as it is made: the digest names the blob, and the size
      // is the number of bytes that were copied.
      let copied = DigestingChunkReader(
        source.chunks,
        using: hasher,
      )
      let staged = try files.stageFile(
        copying: copied,
        in: attachments.url,
      )
      let found = copied.streamed

      try publishBlob(
        staged,
        digest: found.digest,
        in: root,
      )

      descriptors.append(
        ResultAttachment(
          name: source.name,
          digest: found.digest,
          sizeBytes: found.length,
          mediaType: MediaTypeTable.mediaType(forFileNamed: source.name),
        ),
      )
    }

    return descriptors
  }

  /// Makes the folders down to the blob and publishes the staged file as it, unless the same
  /// bytes are already there. A blob is never changed once it is published.
  private func publishBlob(
    _ staged: URL,
    digest: String,
    in run: StoreFile,
  ) throws(StoreWritingError) {
    let names = StoreLayout.attachmentNames(digest: digest)
    var place = run

    do throws(StoreWritingError) {
      for name in names.folders {
        place = place.appending(name)
        try files.ensureFolder(at: place.url)
      }

      let blob = place.appending(names.blob)
      let kind = try reading { () throws(StoreProblem) in
        try access.kind(of: blob)
      }

      switch kind {
      case nil:
        try files.publishStagedFile(
          staged,
          at: blob.url,
        )
      case .file?:
        files.discard(staged)
      default:
        throw StoreWritingError.unwritable(
          location: blob.location,
          reason: "it is not a regular file",
        )
      }
    } catch {
      files.discard(staged)

      throw error
    }
  }
}

extension RunWriting {
  /// Keeps files whose bytes are held as evidence.
  func ingest(
    _ sources: [AttachmentFile],
    into run: OpenRun,
  ) throws(StoreWritingError) -> [ResultAttachment] {
    try ingest(
      sources.map { source in
        AttachmentSource(
          name: source.name,
          chunks: BufferedChunkReader(bytes: source.bytes),
        )
      },
      into: run,
    )
  }
}
