import Testing
@testable import UseCasesCore

struct BufferedChunkReaderTests {
  @Test(arguments: ChunkSamples.sizes)
  func `bytes that are held are handed out in chunks of at most 64 KiB, and make up the bytes`(
    size: Int,
  ) {
    let bytes = ChunkSamples.bytes(count: size)
    let reader = BufferedChunkReader(bytes: bytes)
    var found: [[UInt8]] = []

    while true {
      let chunk = reader.nextChunk()

      guard !chunk.isEmpty else {
        break
      }

      found.append(chunk)
    }

    #expect(found.flatMap(\.self) == bytes)
    #expect(found.allSatisfy { $0.count <= 65536 })
    #expect(found.count == (size + 65535) / 65536)
    #expect(reader.length == size)
    #expect(reader.nextChunk().isEmpty)
  }
}
