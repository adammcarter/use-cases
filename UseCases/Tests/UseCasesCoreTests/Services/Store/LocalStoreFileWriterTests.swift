import Foundation
import Testing
@testable import UseCasesCore

struct LocalStoreFileWriterTests {
  private let directory: TemporaryDirectory
  private let writer = LocalStoreFileWriter()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func text(_ path: String) throws -> String {
    try String(
      contentsOf: directory.location(of: path),
      encoding: .utf8,
    )
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.url.path).sorted()
  }

  @Test
  func `a folder is made, and a folder that is there is fine`() throws {
    let folder = directory.location(of: "store")

    try writer.ensureFolder(at: folder)
    try writer.ensureFolder(at: folder)

    #expect(try names() == ["store"])
  }

  @Test
  func `a file in the place of a folder is an error that says so`() throws {
    try directory.write("store", "not a folder")

    let error = #expect(throws: StoreWritingError.self) {
      try writer.ensureFolder(at: directory.location(of: "store"))
    }

    #expect(error?.description.contains("it is a file, not a folder") == true)
  }

  @Test
  func `a symlink in the place of a folder is an error that says so, even to a folder`() throws {
    try directory.makeDirectory("real")
    try directory.symlink("store", to: directory.location(of: "real").path)

    let error = #expect(throws: StoreWritingError.self) {
      try writer.ensureFolder(at: directory.location(of: "store"))
    }

    #expect(error?.description.contains("it is a symlink, not a folder") == true)
  }

  @Test
  func `a folder whose parent is not there is an error`() {
    #expect(throws: StoreWritingError.self) {
      try writer.ensureFolder(at: directory.location(of: "missing/store"))
    }
  }

  @Test
  func `a new file is written whole`() throws {
    try writer.createFile(
      Array("hello\n".utf8),
      at: directory.location(of: "a.txt"),
    )

    #expect(try text("a.txt") == "hello\n")
  }

  @Test
  func `a new file never replaces one that is there`() throws {
    try directory.write("a.txt", "first")

    #expect(throws: StoreWritingError.self) {
      try writer.createFile(
        Array("second".utf8),
        at: directory.location(of: "a.txt"),
      )
    }
    #expect(try text("a.txt") == "first")
  }

  @Test
  func `a replaced file is the new bytes and leaves no temporary file`() throws {
    try directory.write("a.txt", "first")

    try writer.replaceFile(
      Array("second".utf8),
      at: directory.location(of: "a.txt"),
    )

    #expect(try text("a.txt") == "second")
    #expect(try names() == ["a.txt"])
  }

  @Test
  func `a file that was not there is made by replacing it`() throws {
    try writer.replaceFile(
      Array("new".utf8),
      at: directory.location(of: "a.txt"),
    )

    #expect(try text("a.txt") == "new")
  }

  @Test
  func `bytes are added to the end of a file`() throws {
    try directory.write("log.jsonl", "one\n")

    try writer.append(
      Array("two\n".utf8),
      to: directory.location(of: "log.jsonl"),
    )

    #expect(try text("log.jsonl") == "one\ntwo\n")
  }

  @Test
  func `bytes are never added to a file that is not there`() throws {
    #expect(throws: StoreWritingError.self) {
      try writer.append(
        Array("two\n".utf8),
        to: directory.location(of: "log.jsonl"),
      )
    }
    #expect(try names().isEmpty)
  }

  @Test
  func `a published file appears whole and leaves no temporary file`() throws {
    try writer.publishFile(
      Array("sealed".utf8),
      at: directory.location(of: "completion.json"),
    )

    #expect(try text("completion.json") == "sealed")
    #expect(try names() == ["completion.json"])
  }

  @Test
  func `a published executable file is runnable and leaves no temporary file`() throws {
    try writer.publishExecutableFile(
      Array("#!/bin/sh\n".utf8),
      at: directory.location(of: "pre-commit"),
    )

    #expect(FileManager.default.isExecutableFile(atPath: directory.location(of: "pre-commit").path))
    #expect(try text("pre-commit") == "#!/bin/sh\n")
    #expect(try names() == ["pre-commit"])
  }

  @Test
  func `a published executable file never overwrites the one that is there`() throws {
    try directory.write("pre-commit", "first")

    #expect(throws: StoreWritingError.self) {
      try writer.publishExecutableFile(
        Array("second".utf8),
        at: directory.location(of: "pre-commit"),
      )
    }
    #expect(try text("pre-commit") == "first")
    #expect(try names() == ["pre-commit"])
  }

  @Test
  func `a published file never overwrites the one that is there`() throws {
    try directory.write("completion.json", "first")

    #expect(throws: StoreWritingError.self) {
      try writer.publishFile(
        Array("second".utf8),
        at: directory.location(of: "completion.json"),
      )
    }
    #expect(try text("completion.json") == "first")
    #expect(try names() == ["completion.json"])
  }

  @Test
  func `a folder is published under its final name`() throws {
    try directory.write(".tmp-1/run.json", "{}")

    try writer.publishFolder(
      directory.location(of: ".tmp-1"),
      as: directory.location(of: "1"),
    )

    #expect(try text("1/run.json") == "{}")
    #expect(try names() == ["1"])
  }

  @Test(arguments: [true, false])
  func `a folder is never published over a name that is taken`(isEmpty: Bool) throws {
    try directory.write(".tmp-1/run.json", "new")
    if isEmpty {
      try directory.makeDirectory("1")
    } else {
      try directory.write("1/run.json", "old")
    }

    #expect(throws: StoreWritingError.self) {
      try writer.publishFolder(
        directory.location(of: ".tmp-1"),
        as: directory.location(of: "1"),
      )
    }
    #expect(try text(".tmp-1/run.json") == "new")
  }

  @Test
  func `discarding removes a folder and everything in it, and a missing item is no error`() throws {
    try directory.write(".tmp-1/run.json", "{}")

    writer.discard(directory.location(of: ".tmp-1"))
    writer.discard(directory.location(of: ".tmp-1"))

    #expect(try names().isEmpty)
  }
}
