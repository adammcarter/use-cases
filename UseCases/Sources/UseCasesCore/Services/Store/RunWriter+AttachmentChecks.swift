extension RunWriter {
  /// Every blob the result names has to be in the run and be the bytes it names: a run is not
  /// sealed over evidence that is already damaged (chapter 12 §21 step 2).
  func requireIntactAttachments(
    of result: StoredResult,
    in run: StoreFile,
  ) throws(StoreWritingError) {
    for attachment in result.detail?.attachments ?? [] {
      let path = StoreLayout.attachmentPath(digest: attachment.digest)
      let streamed = try reading { () throws(StoreProblem) in
        try access.streamedFile(
          below: run,
          path: path,
          using: hasher,
        )
      }

      if let damage = damage(
        of: attachment,
        found: streamed,
      ) {
        throw .damaged(.corrupt("\(run.location)/\(path)", damage.description))
      }
    }
  }

  private func damage(
    of attachment: ResultAttachment,
    found: StreamedFile?,
  ) -> AttachmentDamage? {
    guard let found else {
      return .missing
    }
    guard found.length == attachment.sizeBytes else {
      return .wrongSize(
        expected: attachment.sizeBytes,
        found: found.length,
      )
    }

    return found.digest == attachment.digest ? nil : .wrongDigest
  }
}
