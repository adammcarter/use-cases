import Foundation
import Testing
@testable import UseCasesCore

struct LocalFileSystemTests {
  private let fileSystem = LocalFileSystem()

  private func sortedEntries(in directory: TemporaryDirectory) throws -> [FileEntry] {
    try fileSystem.entries(in: directory.url).sorted { lhs, rhs in
      lhs.name < rhs.name
    }
  }

  @Test
  func `files, folders and symlinks are told apart and a symlink is never followed`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("file.txt", "x")
    try directory.makeDirectory("folder")
    try directory.symlink("file-link", to: "file.txt")
    try directory.symlink("folder-link", to: "folder")
    try directory.symlink("dangling-link", to: "nowhere")

    let entries = try sortedEntries(in: directory)

    #expect(
      entries == [
        FileEntry(name: "dangling-link", kind: .symlink),
        FileEntry(name: "file-link", kind: .symlink),
        FileEntry(name: "file.txt", kind: .file),
        FileEntry(name: "folder", kind: .directory),
        FileEntry(name: "folder-link", kind: .symlink),
      ],
    )
  }

  @Test
  func `an empty folder has no entries`() throws {
    let directory = try TemporaryDirectory()

    #expect(try fileSystem.entries(in: directory.url).isEmpty)
  }

  @Test
  func `a missing folder is not found`() throws {
    let directory = try TemporaryDirectory()
    let missing = directory.location(of: "missing")

    #expect(throws: FileSystemError.notFound(missing)) {
      try fileSystem.entries(in: missing)
    }
  }

  @Test
  func `a file or symlink that is not there is not found, never unreadable`() throws {
    let directory = try TemporaryDirectory()
    let missing = directory.location(of: "missing")

    #expect(throws: FileSystemError.notFound(missing)) {
      try fileSystem.readBytes(at: missing)
    }
    #expect(throws: FileSystemError.notFound(missing)) {
      try fileSystem.targetText(ofSymlinkAt: missing)
    }
  }

  @Test
  func `a file is not a folder to list`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("file.txt")

    #expect(throws: FileSystemError.self) {
      try fileSystem.entries(in: directory.location(of: "file.txt"))
    }
  }

  @Test
  func `what is at a location is its own kind, and a symlink there is a symlink`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.txt")
    try directory.makeDirectory("d")
    try directory.symlink("l", to: "d")
    try directory.symlink("dangling", to: "gone")

    #expect(try fileSystem.kindOfItem(at: directory.location(of: "a.txt")) == .file)
    #expect(try fileSystem.kindOfItem(at: directory.location(of: "d")) == .directory)
    #expect(try fileSystem.kindOfItem(at: directory.location(of: "l")) == .symlink)
    #expect(try fileSystem.kindOfItem(at: directory.location(of: "dangling")) == .symlink)
  }

  @Test(arguments: ["missing", "a.txt/below", "missing/deeper/still"])
  func `nothing there is no kind`(path: String) throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.txt")

    #expect(try fileSystem.kindOfItem(at: directory.location(of: path)) == nil)
  }

  @Test
  func `a name keeps the Unicode form the file system holds`() throws {
    let directory = try TemporaryDirectory()
    let decomposed = "cafe\u{301}.yml"
    try directory.write(decomposed)

    let names = try fileSystem.entries(in: directory.url).map(\.name)

    #expect(names.count == 1)
    #expect(names.first?.isExactlyEqual(to: decomposed) == true)
  }

  @Test
  func `a file reads as its text`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.yml", "root: true\ncaf\u{E9}\n")

    #expect(try fileSystem
      .readText(at: directory.location(of: "a.yml")) == "root: true\ncaf\u{E9}\n")
  }

  @Test
  func `a byte order mark is kept for the reader to handle`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.yml", bytes: [0xEF, 0xBB, 0xBF, 0x61])

    let text = try fileSystem.readText(at: directory.location(of: "a.yml"))

    #expect(text.unicodeScalars.map(\.value) == [0xFEFF, 0x61])
  }

  @Test(arguments: [[0xFF], [0x61, 0xC3], [0xC0, 0x80], [0xED, 0xA0, 0x80]] as [[UInt8]])
  func `bytes that are not UTF-8 are refused`(bytes: [UInt8]) throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.yml", bytes: bytes)
    let file = directory.location(of: "a.yml")

    #expect(throws: FileSystemError.notUTF8(file)) {
      try fileSystem.readText(at: file)
    }
  }

  @Test
  func `a missing file cannot be read`() throws {
    let directory = try TemporaryDirectory()

    #expect(throws: FileSystemError.self) {
      try fileSystem.readText(at: directory.location(of: "missing.yml"))
    }
  }

  @Test
  func `the canonical location resolves symlinks and dots`() throws {
    let directory = try TemporaryDirectory()
    try directory.makeDirectory("real/inner")
    try directory.symlink("alias", to: "real")

    let spelled = directory.location(of: "alias/inner/../inner")

    #expect(fileSystem.canonicalLocation(of: spelled) == directory.location(of: "real/inner"))
  }

  @Test
  func `a named pipe is other, and is neither read nor opened to find that out`() throws {
    let directory = try TemporaryDirectory()
    try directory.makeFIFO("use-cases.yml")

    #expect(try fileSystem.kindOfItem(at: directory.location(of: "use-cases.yml")) == .other)
    #expect(try fileSystem.entries(in: directory.url) == [FileEntry(
      name: "use-cases.yml",
      kind: .other,
    )])
  }
}
