import Foundation
@testable import UseCasesCore

/// The local attachment reader, telling a log how big each chunk of what it opened was.
struct AccountingAttachmentReader: AttachmentReading {
  private let local = LocalAttachmentReader()
  let log: ChunkLog

  func chunks(of file: URL) throws(AttachmentReadingError) -> any FileChunkReading {
    try AccountingChunkReader(
      local.chunks(of: file),
      log: log,
    )
  }
}
