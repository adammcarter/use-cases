import Foundation
import Testing
@testable import UseCasesCore

struct FileSystemChunksTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a file system that streams and one that does not give the same bytes`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try directory.write("file", bytes: bytes)
    let location = directory.location(of: "file")

    let streamed = try LocalFileSystem().chunks(of: location).remainingBytes()
    let whole = try WholeFileSystem().chunks(of: location).remainingBytes()

    #expect(streamed == bytes)
    #expect(whole == bytes)
  }

  @Test
  func `a file system that cannot stream says what reading it whole says`() {
    let missing = directory.location(of: "nothing")

    #expect(throws: FileSystemError.notFound(missing)) {
      try WholeFileSystem().chunks(of: missing)
    }
  }

  @Test
  func `a file system that cannot stream gives a file whole, in chunks`() throws {
    let bytes = ChunkSamples.bytes(count: 70000)
    try directory.write("file", bytes: bytes)

    let reader = try WholeFileSystem().chunks(of: directory.location(of: "file"))

    #expect(reader.length == 70000)
    #expect(try reader.nextChunk().count == 65536)
    #expect(try reader.nextChunk().count == 70000 - 65536)
    #expect(try reader.nextChunk().isEmpty)
  }
}
