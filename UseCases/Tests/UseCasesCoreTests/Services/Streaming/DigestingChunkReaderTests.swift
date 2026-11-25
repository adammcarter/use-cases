import Foundation
import Testing
@testable import UseCasesCore

struct DigestingChunkReaderTests {
  private let hasher = SHA256Hasher()

  @Test(arguments: ChunkSamples.sizes)
  func `what went by is digested and counted, and handed on unchanged`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)
    let reader = DigestingChunkReader(
      BufferedChunkReader(bytes: bytes),
      using: hasher,
    )

    #expect(try reader.remainingBytes() == bytes)
    #expect(
      reader.streamed == StreamedFile(
        digest: hasher.sha256Hex(of: bytes),
        length: size,
      ),
    )
  }

  @Test
  func `nothing read is the digest of nothing`() {
    let reader = DigestingChunkReader(
      BufferedChunkReader(bytes: []),
      using: hasher,
    )

    #expect(reader.streamed
      .digest == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(reader.streamed.length == 0)
  }

  @Test
  func `the length is the bytes that went by, whatever the source said`() throws {
    let source = ScriptedChunkReader(
      chunks: [Array("abc".utf8), Array("defgh".utf8)],
      length: 3,
    )
    let reader = DigestingChunkReader(
      source,
      using: hasher,
    )

    _ = try reader.remainingBytes()

    #expect(reader.length == 3)
    #expect(reader.streamed.length == 8)
    #expect(reader.streamed.digest == hasher.sha256Hex(of: Array("abcdefgh".utf8)))
  }

  @Test
  func `a failure of the source is the failure of the reader`() {
    let failure = FileSystemError.notFound(URL(fileURLWithPath: "/gone"))
    let reader = DigestingChunkReader(
      ScriptedChunkReader(
        chunks: [[1, 2]],
        failure: failure,
      ),
      using: hasher,
    )

    #expect(throws: failure) {
      try reader.remainingBytes()
    }
  }
}
