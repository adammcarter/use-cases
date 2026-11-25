import Foundation
import Testing
@testable import UseCasesCore

struct PlannedFileSystemTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func overlay(_ changes: [PlannedChange]) throws -> PlannedFileSystem {
    try PlannedFileSystem(
      base: LocalFileSystem(),
      plan: WritePlan.making(changes),
      root: directory.url,
    )
  }

  @Test
  func `a file the plan creates is there, holding the plan's bytes, and nothing is written`()
    throws
  {
    let view = try overlay([.create("use-cases/example.yml", "id: x\n")])
    let file = directory.location(of: "use-cases/example.yml")

    #expect(try view.kindOfItem(at: file) == .file)
    #expect(try view.readText(at: file) == "id: x\n")
    #expect(try view.readBytes(at: file) == Array("id: x\n".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
  }

  @Test
  func `the folders above a new file are there, and list it`() throws {
    let view = try overlay([.create("a/b/c.yml", "x")])

    #expect(try view.kindOfItem(at: directory.location(of: "a/b")) == .directory)
    #expect(try view.entries(in: directory.url).map(\.name) == ["a"])
    #expect(try view.entries(in: directory.location(of: "a/b")).map(\.name) == ["c.yml"])
  }

  @Test
  func `a replaced file reads as the plan says and a deleted one is gone from its folder`() throws {
    try directory.write("a.yml", "old")
    try directory.write("b.yml", "old")
    try directory.write("c.yml", "old")

    let view = try overlay([.replace("a.yml", "new"), .delete("b.yml")])

    #expect(try view.readText(at: directory.location(of: "a.yml")) == "new")
    #expect(try view.kindOfItem(at: directory.location(of: "b.yml")) == nil)
    #expect(try view.entries(in: directory.url).map(\.name).sorted() == ["a.yml", "c.yml"])
    #expect(try view.readText(at: directory.location(of: "c.yml")) == "old")
  }

  @Test
  func `what the plan does not touch is the real file system`() throws {
    try directory.write("src/code.swift", "let x = 1")
    try directory.symlink("link", to: "src")

    let view = try overlay([.create("use-cases.yml", "x")])

    #expect(try view.readText(at: directory.location(of: "src/code.swift")) == "let x = 1")
    #expect(try view.kindOfItem(at: directory.location(of: "link")) == .symlink)
    #expect(try view.targetText(ofSymlinkAt: directory.location(of: "link")) == "src")
    #expect(try view.entries(in: directory.location(of: "src")).map(\.name) == ["code.swift"])
  }

  @Test
  func `a folder that is not there and not planned is still not there`() throws {
    let view = try overlay([.create("a.yml", "x")])

    #expect(try view.kindOfItem(at: directory.location(of: "nowhere")) == nil)
    #expect(throws: FileSystemError.self) {
      try view.entries(in: directory.location(of: "nowhere"))
    }
  }

  @Test
  func `a file is found below a folder when the plan puts it there`() throws {
    try directory.makeDirectory("services")

    let view = try overlay([.create("services/pay/use-cases.yml", "x")])

    #expect(view.holdsFile(
      named: "use-cases.yml",
      below: FileEntry(name: "services", kind: .directory),
      in: directory.url,
    ))
    #expect(!view.holdsFile(
      named: "other.yml",
      below: FileEntry(name: "services", kind: .directory),
      in: directory.url,
    ))
  }

  @Test
  func `a file that is not UTF-8 reads as an error`() throws {
    let view = try PlannedFileSystem(
      base: LocalFileSystem(),
      plan: WritePlan(
        changes: [
          FileChange(
            action: .create,
            path: WorkspacePath(validating: "bad.yml"),
            bytes: [0xFF, 0xFE],
          ),
        ],
      ),
      root: directory.url,
    )

    #expect(throws: FileSystemError.self) {
      try view.readText(at: directory.location(of: "bad.yml"))
    }
  }
}
