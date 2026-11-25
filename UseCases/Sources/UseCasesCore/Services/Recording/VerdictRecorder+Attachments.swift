import Foundation

extension VerdictRecorder {
  public func checkAttachments(at locations: [URL]) throws(RecordingError) {
    _ = try openedAttachments(at: locations)
  }

  /// Keeps every attachment as it is now, in the order given. All of them are opened before the
  /// first is kept, so a refusal leaves nothing behind (chapter 13 §12).
  func keptAttachments(at locations: [URL]) throws(RecordingError) -> SpooledAttachments {
    let sources = try openedAttachments(at: locations)

    do {
      return try spooler.spool(sources)
    } catch {
      throw .storage(error.description)
    }
  }

  /// The attachments of a plan, opened to be copied into the run a chunk at a time.
  func attachmentSources(of plan: RecordPlan) throws(RecordingError) -> [AttachmentSource] {
    var sources: [AttachmentSource] = []

    for attachment in plan.result.attachments.files {
      try sources.append(
        AttachmentSource(
          name: attachment.name,
          chunks: opened(attachment.file),
        ),
      )
    }

    return sources
  }

  private func openedAttachments(at locations: [URL]) throws(RecordingError) -> [AttachmentSource] {
    var sources: [AttachmentSource] = []
    var names: Set<[UInt8]> = []

    for location in locations {
      let name = location.lastPathComponent

      // Names are compared by their bytes, as every name in the store is.
      guard names.insert(Array(name.utf8)).inserted else {
        throw .duplicateAttachmentName(name)
      }

      try sources.append(
        AttachmentSource(
          name: name,
          chunks: opened(location),
        ),
      )
    }

    return sources
  }

  private func opened(_ location: URL) throws(RecordingError) -> any FileChunkReading {
    do {
      return try reader.chunks(of: location)
    } catch {
      throw Self.refusal(
        of: error,
        reading: location,
      )
    }
  }

  private static func refusal(
    of error: AttachmentReadingError,
    reading location: URL,
  ) -> RecordingError {
    switch error {
    case .missing:
      .attachmentMissing(location.path)
    case .folder:
      .attachmentIsFolder(location.path)
    case .notRegular:
      .attachmentNotRegular(location.path)
    case let .unreadable(reason):
      .attachmentUnreadable(
        path: location.path,
        reason: reason,
      )
    }
  }
}
