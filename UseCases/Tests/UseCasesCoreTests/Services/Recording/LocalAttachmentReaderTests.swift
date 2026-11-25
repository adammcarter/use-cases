import Foundation
import Testing
@testable import UseCasesCore

struct LocalAttachmentReaderTests {
  private let folder: TemporaryDirectory
  private let reader = LocalAttachmentReader()

  init() throws {
    folder = try TemporaryDirectory()
  }

  @Test(arguments: [
    [],
    [0x00],
    [0x0D, 0x0A, 0x00, 0xFF, 0xFE],
    Array(repeating: 0xAB, count: 65536),
    Array(repeating: 0x01, count: 200_001),
  ])
  func `a file is read whole, byte for byte`(bytes: [UInt8]) throws {
    try folder.write(
      "file.bin",
      bytes: bytes,
    )

    #expect(try reader.bytes(of: folder.location(of: "file.bin")) == bytes)
  }

  @Test
  func `a symlink is read through to the file it points at`() throws {
    try folder.write(
      "real.png",
      bytes: [1, 2, 3],
    )
    try folder.symlink(
      "link.png",
      to: "real.png",
    )

    #expect(try reader.bytes(of: folder.location(of: "link.png")) == [1, 2, 3])
  }

  @Test
  func `a name that is not there is missing`() {
    #expect(throws: AttachmentReadingError.missing) {
      try reader.bytes(of: folder.location(of: "nope.png"))
    }
  }

  @Test
  func `a symlink to nothing is missing`() throws {
    try folder.symlink(
      "dangling.png",
      to: "gone.png",
    )

    #expect(throws: AttachmentReadingError.missing) {
      try reader.bytes(of: folder.location(of: "dangling.png"))
    }
  }

  @Test
  func `a name below a file is missing`() throws {
    try folder.write(
      "plain.txt",
      "x",
    )

    #expect(throws: AttachmentReadingError.missing) {
      try reader.bytes(of: folder.location(of: "plain.txt/inside.png"))
    }
  }

  @Test
  func `a folder is a folder`() throws {
    try folder.makeDirectory("shots")

    #expect(throws: AttachmentReadingError.folder) {
      try reader.bytes(of: folder.location(of: "shots"))
    }
  }

  @Test
  func `a named pipe is refused and never opened`() throws {
    try folder.makeFIFO("pipe.log")

    #expect(throws: AttachmentReadingError.notRegular) {
      try reader.bytes(of: folder.location(of: "pipe.log"))
    }
  }

  @Test(.enabled(if: getuid() != 0, "root can read any file"))
  func `a file the system will not let be read is unreadable`() throws {
    try folder.write(
      "secret.txt",
      "x",
    )
    let file = folder.location(of: "secret.txt")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000],
      ofItemAtPath: file.path,
    )

    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: file.path,
      )
    }

    do {
      _ = try reader.bytes(of: file)
      Issue.record("the file was read")
    } catch {
      guard case .unreadable = error else {
        Issue.record("not unreadable: \(error)")
        return
      }
    }
  }
}
