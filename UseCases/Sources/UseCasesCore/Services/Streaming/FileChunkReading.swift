/// A file read a chunk at a time, so that hashing or copying it holds no more than a chunk of it
/// (chapter 12 §17). It is read by one caller, one chunk after the other, so it is not shared.
protocol FileChunkReading {
  /// The size of the file when it was opened. A file that is written to while it is read gives
  /// more or fewer bytes than this, which a reader that needs the size first has to look for.
  var length: Int { get }

  /// The next chunk of at most ``FileChunk/size`` bytes, in order. Empty at the end of the file,
  /// and after it.
  func nextChunk() throws(FileSystemError) -> [UInt8]
}

extension FileChunkReading {
  /// The SHA-256 and the length of what is left of the file, read to its end.
  ///
  /// - Parameter hasher: Makes the digest.
  func streamedFile(using hasher: any Hashing) throws(FileSystemError) -> StreamedFile {
    var accumulator = hasher.accumulator()
    var count = 0

    while true {
      let chunk = try nextChunk()

      guard !chunk.isEmpty else {
        break
      }

      accumulator.add(chunk)
      count += chunk.count
    }

    return StreamedFile(
      digest: accumulator.hex(),
      length: count,
    )
  }

  /// Every byte that is left of the file, held whole: for what is known to be small.
  func remainingBytes() throws(FileSystemError) -> [UInt8] {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(length)

    while true {
      let chunk = try nextChunk()

      guard !chunk.isEmpty else {
        return bytes
      }

      bytes.append(contentsOf: chunk)
    }
  }
}
