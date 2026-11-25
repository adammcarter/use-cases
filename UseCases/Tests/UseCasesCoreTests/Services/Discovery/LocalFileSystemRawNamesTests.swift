import Foundation
import Testing
@testable import UseCasesCore

struct LocalFileSystemRawNamesTests {
  private let fileSystem = LocalFileSystem()
  private let invalidName: [UInt8] = Array("bad".utf8) + [0xFF, 0xFE] + Array(".js".utf8)

  @Test
  func `a name that is not UTF-8 is written in ASCII with its other bytes escaped`() {
    #expect(LocalFileSystem.escaped(invalidName) == #"bad\xFF\xFE.js"#)
    #expect(LocalFileSystem.escaped([0x61, 0x0A, 0x5C, 0x00, 0x7F]) == #"a\x0A\x5C\x00\x7F"#)
  }

  @Test
  func `a listing has every name once and never . or ..`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("a.txt")
    try directory.write(".hidden")
    try directory.makeDirectory("sub")

    let names = try fileSystem.entries(in: directory.url).map(\.name).sorted()

    #expect(names == [".hidden", "a.txt", "sub"])
  }

  @Test
  func `a name that is valid UTF-8 is its own text, in the form the disk stores`() throws {
    let directory = try TemporaryDirectory()
    let name = "cafe\u{301} \u{65E5}\u{672C}.txt"
    try directory.write(name)

    let entry = try #require(fileSystem.entries(in: directory.url).first)

    #expect(entry.isNameUTF8)
    #expect(entry.name.isExactlyEqual(to: name))
  }

  @Test
  func `a file whose name is not UTF-8 is listed as a file with an escaped name`() throws {
    let directory = try TemporaryDirectory()

    guard try directory.makeFile(namedByBytes: invalidName, in: "src") else {
      try Test.cancel("this file system refuses a file name that is not valid UTF-8")
    }

    let entry = try #require(fileSystem.entries(in: directory.location(of: "src")).first)

    #expect(entry.name == #"bad\xFF\xFE.js"#)
    #expect(entry.kind == .file)
    #expect(!entry.isNameUTF8)
  }

  @Test
  func `a name that is not UTF-8 is a warning in the scanned tree, never silent`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.writeUseCase()

    guard try fixture.directory.makeFile(namedByBytes: invalidName, in: "src") else {
      try Test.cancel("this file system refuses a file name that is not valid UTF-8")
    }

    let resolution = try fixture.resolved()

    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: #"bad\xFF\xFE.js"#).count == 1)
    #expect(resolution.warnings(containing: "not valid UTF-8").count == 1)
  }

  @Test
  func `a name that is not UTF-8 inside a use_cases_dir is INVALID`() throws {
    let fixture = try WorkspaceFixture()

    guard try fixture.directory.makeFile(namedByBytes: invalidName, in: "use-cases") else {
      try Test.cancel("this file system refuses a file name that is not valid UTF-8")
    }

    let problems = fixture.problems()

    #expect(problems.count == 1)
    #expect(problems.first?.contains(#"bad\xFF\xFE.js"#) == true)
  }

  @Test
  func `a scope inside a folder whose name is not UTF-8 is found by its raw bytes`() throws {
    let directory = try TemporaryDirectory()

    guard
      try directory.makeDirectory(namedByBytes: invalidName, in: "pkg"),
      directory.makeFile(named: "use-cases.yml", inFolderNamedByBytes: invalidName, in: "pkg")
    else {
      try Test.cancel("this file system refuses a folder name that is not valid UTF-8")
    }

    let folder = try #require(fileSystem.entries(in: directory.location(of: "pkg")).first)

    #expect(folder.kind == .directory)
    #expect(
      fileSystem.holdsFile(
        named: "use-cases.yml",
        below: folder,
        in: directory.location(of: "pkg"),
      ),
    )
    #expect(
      !fileSystem.holdsFile(
        named: "other.yml",
        below: folder,
        in: directory.location(of: "pkg"),
      ),
    )
  }

  @Test(.enabled(if: getuid() != 0))
  func `a name that cannot be looked at is a failure, not a name that has gone`() throws {
    let directory = try TemporaryDirectory()

    guard try directory.makeFile(namedByBytes: invalidName, in: "src") else {
      try Test.cancel("this file system refuses a file name that is not valid UTF-8")
    }

    let folder = directory.location(of: "src")
    // Readable but not searchable: the names can be listed, and none can be looked at.
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: folder.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    }

    #expect(throws: FileSystemError.self) {
      try fileSystem.entries(in: folder)
    }
  }
}
