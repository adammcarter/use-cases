import Foundation

/// Reads a file that was given as evidence, exactly as it is (chapter 12 §16).
protocol AttachmentReading: Sendable {
  /// The regular file at a place, opened to be read a chunk at a time: an attachment is as big as
  /// the person made it. A symlink is read through to the file it points at, as the person who
  /// named it meant.
  func chunks(of file: URL) throws(AttachmentReadingError) -> any FileChunkReading
}

extension AttachmentReading {
  /// The exact bytes of the regular file at a place, held whole: for a file known to be small.
  func bytes(of file: URL) throws(AttachmentReadingError) -> [UInt8] {
    let reader = try chunks(of: file)

    do {
      return try reader.remainingBytes()
    } catch {
      throw AttachmentReadingError(reading: error)
    }
  }
}
