import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The command cores' filesystem seam (io.ts): the read-modify-rewrite ledger
/// "append", the mode-preserving atomic write, and the directory listing.
struct MarkerCommandFilesTests {
  private typealias Fixtures = MarkerCommandsFixtures

  private func mode(_ path: String) throws -> Int {
    var status = stat()
    try #require(stat(path, &status) == 0)
    return Int(status.st_mode & 0o7777)
  }

  @Test(arguments: MarkerCommandsGoldenCorpus.appendCaseNames)
  func `a ledger line is added by rewriting the whole file as the TypeScript does`(
    caseName: String,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: "append_jsonl_line")
    let (directory, root) = try Fixtures.temporaryRoot()
    let nested = entry["nested"]?.boolValue == true
    let path = nested ? root + "/deep/er/ledger.jsonl" : root + "/ledger.jsonl"
    if let before = entry["before"]?.stringValue {
      try NodeFile.writeText(before, atPath: path)
      try #require(chmod(path, 0o640) == 0)
    }

    try MarkerCommandFiles.appendJSONLine(
      #require(entry["line"]?.stringValue),
      toPath: path,
      files: LocalTextFiles(),
    )

    #expect(try NodeFile.readText(atPath: path) == #require(entry["after"]?.stringValue))
    #expect(try mode(path) == Fixtures.optionalInteger(entry, "mode"))
    _ = directory
  }

  @Test(arguments: MarkerCommandsGoldenCorpus.writeTextCaseNames)
  func `an atomic write keeps or drops the destination's mode as the TypeScript does`(
    caseName: String,
  ) throws {
    let entry = try Fixtures.entry(caseName, in: "write_text")
    let (directory, root) = try Fixtures.temporaryRoot()
    let path = root + "/tool.sh"
    if let initial = entry["initial_mode"]?.numberValue {
      try NodeFile.writeText("old\n", atPath: path)
      try #require(chmod(path, mode_t(initial)) == 0)
    }

    try LocalTextFiles().writeText(
      "new\n",
      toPath: path,
      preservingMode: #require(entry["preserve_mode"]?.boolValue as Bool?),
    )

    #expect(try NodeFile.readText(atPath: path) == #require(entry["contents"]?.stringValue))
    #expect(try mode(path) == Fixtures.optionalInteger(entry, "mode"))
    #expect(try NodeFile.directoryNames(atPath: root) == MarkersFixtures.strings(
      entry,
      "directory_entries",
    ))
    _ = directory
  }

  @Test
  func `the temporary file name carries the injected clock's milliseconds`() throws {
    let (directory, root) = try Fixtures.temporaryRoot()
    let path = root + "/ledger.jsonl"
    let blocker = "\(path).tmp-\(getpid())-1234567"
    try NodeFile.makeDirectories(atPath: blocker)

    let files = LocalTextFiles(currentMilliseconds: { 1_234_567 })
    #expect(throws: FileAccessError(errorNumber: EISDIR, operation: "open", path: blocker)) {
      try files.writeText("x\n", toPath: path)
    }
    #expect(throws: Never.self) {
      try LocalTextFiles(currentMilliseconds: { 7 }).writeText("x\n", toPath: path)
    }
    _ = directory
  }

  @Test
  func `a directory lists each entry as what it is, never what a symlink points at`() throws {
    let (directory, root) = try Fixtures.temporaryRoot()
    try NodeFile.makeDirectories(atPath: root + "/b-directory")
    try NodeFile.writeText("x", atPath: root + "/a-file")
    try #require(symlink("b-directory", root + "/c-link") == 0)
    try #require(symlink("nowhere", root + "/d-dangling") == 0)
    try #require(mkfifo(root + "/e-fifo", 0o644) == 0)

    let entries = try LocalTextFiles().listDirectory(atPath: root)

    #expect(entries == [
      MarkerDirectoryEntry(name: "a-file", isDirectory: false, isFile: true, isSymbolicLink: false),
      MarkerDirectoryEntry(
        name: "b-directory",
        isDirectory: true,
        isFile: false,
        isSymbolicLink: false,
      ),
      MarkerDirectoryEntry(name: "c-link", isDirectory: false, isFile: false, isSymbolicLink: true),
      MarkerDirectoryEntry(
        name: "d-dangling",
        isDirectory: false,
        isFile: false,
        isSymbolicLink: true,
      ),
      MarkerDirectoryEntry(
        name: "e-fifo",
        isDirectory: false,
        isFile: false,
        isSymbolicLink: false,
      ),
    ])
    #expect(throws: FileAccessError(
      errorNumber: ENOENT,
      operation: "scandir",
      path: root + "/missing",
    )) {
      try LocalTextFiles().listDirectory(atPath: root + "/missing")
    }
    #expect(throws: FileAccessError(
      errorNumber: ENOTDIR,
      operation: "scandir",
      path: root + "/a-file",
    )) {
      try LocalTextFiles().listDirectory(atPath: root + "/a-file")
    }
    _ = directory
  }

  @Test
  func `existence follows symlinks as existsSync does`() throws {
    let (directory, root) = try Fixtures.temporaryRoot()
    try NodeFile.writeText("x", atPath: root + "/file")
    try #require(symlink("file", root + "/link") == 0)
    try #require(symlink("nowhere", root + "/dangling") == 0)
    let files = LocalTextFiles()

    #expect(files.exists(atPath: root + "/file"))
    #expect(files.exists(atPath: root + "/link"))
    #expect(files.exists(atPath: root))
    #expect(!files.exists(atPath: root + "/dangling"))
    #expect(!files.exists(atPath: root + "/missing"))
    _ = directory
  }
}
