import Foundation
import Testing
@testable import UseCasesCore

struct FileContentReaderChunksTests {
  private let reader = FileContentReader(fileSystem: LocalFileSystem())
  private let directory: TemporaryDirectory
  private let context: DiscoveryContext

  init() throws {
    directory = try TemporaryDirectory()
    context = DiscoveryContext(
      rootDirectory: directory.url,
      builtInExcludes: [],
      configuredExcludes: [],
    )
  }

  private func path(_ text: String) throws -> WorkspacePath {
    try WorkspacePath(validating: text)
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a file is given in chunks that are its bytes`(size: Int) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try directory.write("file.bin", bytes: bytes)

    let chunks = try reader.chunks(
      of: path("file.bin"),
      in: context,
    )

    #expect(try chunks.remainingBytes() == bytes)
    #expect(
      try reader.bytes(of: path("file.bin"), in: context) == bytes,
    )
  }

  @Test
  func `a symlink is given as the text it points with, never what is there`() throws {
    try directory.write("target.txt", "what is there")
    try directory.symlink("link", to: "target.txt")

    let chunks = try reader.chunks(
      of: path("link"),
      in: context,
    )

    #expect(try chunks.remainingBytes() == Array("target.txt".utf8))
  }

  @Test
  func `a folder, and a file that is not there, are refused as the bytes of them are`() throws {
    try directory.makeDirectory("folder")

    #expect(throws: FileContentError.notAFile(.directory)) {
      try reader.chunks(of: path("folder"), in: context)
    }
    #expect(throws: FileContentError.missing) {
      try reader.chunks(of: path("nothing"), in: context)
    }
    #expect(throws: FileContentError.notAFile(.directory)) {
      try reader.bytes(of: path("folder"), in: context)
    }
    #expect(throws: FileContentError.missing) {
      try reader.bytes(of: path("nothing"), in: context)
    }
  }
}
