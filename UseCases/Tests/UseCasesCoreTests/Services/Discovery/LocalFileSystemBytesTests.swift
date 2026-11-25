import Foundation
import Testing
@testable import UseCasesCore

struct LocalFileSystemBytesTests {
  private let fileSystem = LocalFileSystem()

  @Test
  func `a file's bytes come back exactly, whatever they are`() throws {
    let directory = try TemporaryDirectory()
    let bytes: [UInt8] = [0xEF, 0xBB, 0xBF, 0xFF, 0x00, 0x0D, 0x0A, 0x80]
    try directory.write("blob.bin", bytes: bytes)

    #expect(try fileSystem.readBytes(at: directory.location(of: "blob.bin")) == bytes)
  }

  @Test
  func `an empty file has no bytes`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("empty.txt", "")

    #expect(try fileSystem.readBytes(at: directory.location(of: "empty.txt")).isEmpty)
  }

  @Test
  func `a missing file cannot be read`() throws {
    let directory = try TemporaryDirectory()

    #expect(throws: FileSystemError.self) {
      try fileSystem.readBytes(at: directory.location(of: "missing.txt"))
    }
  }

  @Test(.enabled(if: getuid() != 0))
  func `a file without read permission cannot be read`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("locked.txt", "x")
    let locked = directory.location(of: "locked.txt")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
    }

    #expect(throws: FileSystemError.self) {
      try fileSystem.readBytes(at: locked)
    }
  }

  @Test(arguments: ["file.txt", "../../outside.js", "/etc/hosts", "nowhere"])
  func `a symlink holds the text it points with, never what is there`(target: String) throws {
    let directory = try TemporaryDirectory()
    try directory.write("file.txt", "other text")
    try directory.symlink("link", to: target)

    #expect(try fileSystem.targetText(ofSymlinkAt: directory.location(of: "link")) == target)
  }

  @Test
  func `a plain file is not a symlink to read`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("file.txt", "x")

    #expect(throws: FileSystemError.self) {
      try fileSystem.targetText(ofSymlinkAt: directory.location(of: "file.txt"))
    }
  }
}
