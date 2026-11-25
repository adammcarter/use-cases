import Foundation
import Testing
@testable import UseCasesCore

struct PosixChunkReaderTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func chunks(of reader: PosixChunkReader) throws -> [[UInt8]] {
    var found: [[UInt8]] = []

    while true {
      let chunk = try reader.nextChunk()

      guard !chunk.isEmpty else {
        return found
      }

      found.append(chunk)
    }
  }

  @Test(arguments: ChunkSamples.sizes)
  func `a file is read in chunks of at most 64 KiB that make up its bytes again`(
    size: Int,
  ) throws {
    let bytes = ChunkSamples.bytes(count: size)
    try directory.write("file", bytes: bytes)

    let reader = try PosixChunkReader(opening: directory.location(of: "file"))
    let found = try chunks(of: reader)

    #expect(found.flatMap(\.self) == bytes)
    #expect(found.allSatisfy { $0.count <= 65536 })
    #expect(found.count == (size + 65535) / 65536)
    #expect(reader.length == size)
  }

  @Test
  func `the end of a file stays the end`() throws {
    try directory.write("file", "abc")
    let reader = try PosixChunkReader(opening: directory.location(of: "file"))

    #expect(try reader.nextChunk() == Array("abc".utf8))
    #expect(try reader.nextChunk().isEmpty)
    #expect(try reader.nextChunk().isEmpty)
  }

  @Test
  func `a file that is not there is not found`() {
    let missing = directory.location(of: "nothing")

    #expect(throws: FileSystemError.notFound(missing)) {
      try PosixChunkReader(opening: missing)
    }
  }

  @Test
  func `a folder is not read`() throws {
    try directory.makeDirectory("folder")

    #expect(throws: FileSystemError.self) {
      try PosixChunkReader(opening: directory.location(of: "folder"))
    }
  }

  @Test
  func `a symlink is read through to its file, as the bytes of a file are`() throws {
    try directory.write("file", "behind")
    try directory.symlink("link", to: "file")

    let reader = try PosixChunkReader(opening: directory.location(of: "link"))

    #expect(try reader.remainingBytes() == Array("behind".utf8))
  }

  @Test(.enabled(if: getuid() != 0, "permissions do not stop root"))
  func `a file the system will not open is unreadable, with the reason`() throws {
    try directory.write("shut", "x")
    let location = directory.location(of: "shut")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: location.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: location.path,
      )
    }

    do {
      _ = try PosixChunkReader(opening: location)
      Issue.record("opened")
    } catch {
      guard case let .unreadable(url, reason) = error else {
        Issue.record("not unreadable: \(error)")
        return
      }

      #expect(url == location)
      #expect(!reason.isEmpty)
    }
  }

  @Test
  func `a file written to while it is read gives more than its length said`() throws {
    try directory.write("file", "abc")
    let location = directory.location(of: "file")
    let reader = try PosixChunkReader(opening: location)
    let handle = try FileHandle(forWritingTo: location)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("def".utf8))
    try handle.close()

    #expect(reader.length == 3)
    #expect(try reader.remainingBytes() == Array("abcdef".utf8))
  }
}
