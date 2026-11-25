/// Bytes that are already held, handed out a chunk at a time like a file: for what is small, or
/// what a file system that cannot stream gives whole.
final class BufferedChunkReader: FileChunkReading {
  let length: Int

  private let bytes: [UInt8]
  private var offset = 0

  init(bytes: [UInt8]) {
    self.bytes = bytes
    length = bytes.count
  }

  func nextChunk() -> [UInt8] {
    let end = min(offset + FileChunk.size, bytes.count)
    let chunk = Array(bytes[offset ..< end])

    offset = end

    return chunk
  }
}
