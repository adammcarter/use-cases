@testable import UseCasesCore

/// A chunk reader that tells a log how big each of its chunks was.
final class AccountingChunkReader: FileChunkReading {
  private let source: any FileChunkReading
  private let log: ChunkLog

  var length: Int {
    source.length
  }

  init(
    _ source: any FileChunkReading,
    log: ChunkLog,
  ) {
    self.source = source
    self.log = log
    log.open()
  }

  func nextChunk() throws(FileSystemError) -> [UInt8] {
    let chunk = try source.nextChunk()

    log.read(chunk: chunk.count)

    return chunk
  }
}
