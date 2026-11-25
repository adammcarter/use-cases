/// A chunk reader that hands on every chunk of another and keeps the SHA-256 and the length of
/// what went by, so that a file copied is hashed and measured in the same pass, and the length is
/// the number of bytes that were copied, whatever the file's size said before.
final class DigestingChunkReader: FileChunkReading {
  private let source: any FileChunkReading
  private var accumulator: any DigestAccumulating
  private var count = 0

  var length: Int {
    source.length
  }

  /// What went by so far.
  var streamed: StreamedFile {
    StreamedFile(
      digest: accumulator.hex(),
      length: count,
    )
  }

  /// - Parameters:
  ///   - source: The reader whose chunks are handed on.
  ///   - hasher: Makes the digest.
  init(
    _ source: any FileChunkReading,
    using hasher: any Hashing,
  ) {
    self.source = source
    accumulator = hasher.accumulator()
  }

  func nextChunk() throws(FileSystemError) -> [UInt8] {
    let chunk = try source.nextChunk()

    accumulator.add(chunk)
    count += chunk.count

    return chunk
  }
}
