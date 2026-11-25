import Foundation
@testable import UseCasesCore

/// The sizes at which chunked reading can go wrong, and bytes to read at them.
enum ChunkSamples {
  /// Nothing, one byte, a chunk less one, exactly a chunk, a chunk and one, and several chunks
  /// with a tail.
  static let sizes = [0, 1, 65535, 65536, 65537, 3 * 65536 + 7]

  /// Bytes that are the same every time, and are not text.
  static func bytes(count: Int) -> [UInt8] {
    var state: UInt32 = 2_463_534_242

    return (0 ..< count).map { _ in
      state = state &* 1_664_525 &+ 1_013_904_223

      return UInt8(truncatingIfNeeded: state >> 24)
    }
  }

  /// Text of lines that end the way `ending` says, `count` bytes long, and ended by a line end.
  static func text(
    count: Int,
    lineEnding ending: String = "\n",
  ) -> [UInt8] {
    let line = Array(("some text on a line" + ending).utf8)
    var bytes: [UInt8] = []

    bytes.reserveCapacity(count + line.count)

    while bytes.count < count {
      bytes.append(contentsOf: line)
    }

    return Array(bytes.prefix(count))
  }

  /// Writes a file of `megabytes` MiB of lines of text without growing in memory.
  static func writeLargeFile(
    megabytes: Int,
    to file: URL,
  ) throws {
    _ = FileManager.default.createFile(atPath: file.path, contents: nil)

    let handle = try FileHandle(forWritingTo: file)

    defer {
      try? handle.close()
    }

    let block = Data(text(count: 1 << 20))

    for _ in 0 ..< megabytes {
      try handle.write(contentsOf: block)
    }
  }
}
