import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct AtomicPlanWriterTests {
  private let directory: TemporaryDirectory
  private let writer = AtomicPlanWriter()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func text(_ path: String) throws -> String {
    try String(
      contentsOf: directory.location(of: path),
      encoding: .utf8,
    )
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.location(of: path).path)
  }

  @Test
  func `a new file is made with the folders above it`() throws {
    try writer.apply(
      WritePlan.making([.create("use-cases/deep/example.yml", "id: x\n")]),
      in: directory.url,
    )

    #expect(try text("use-cases/deep/example.yml") == "id: x\n")
  }

  @Test
  func `files are written in the order of the plan`() throws {
    try writer.apply(
      WritePlan.making([
        .create("a.yml", "one"),
        .create("b/c.yml", "two"),
        .create("b/d.yml", "three"),
      ]),
      in: directory.url,
    )

    #expect(try [text("a.yml"), text("b/c.yml"), text("b/d.yml")] == ["one", "two", "three"])
  }

  @Test
  func `a file is replaced whole and leaves nothing beside it`() throws {
    try directory.write("a.yml", "old, and longer than the new")

    try writer.apply(
      WritePlan.making([.replace("a.yml", "new")]),
      in: directory.url,
    )

    #expect(try text("a.yml") == "new")
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == ["a.yml"])
  }

  @Test
  func `a file is deleted`() throws {
    try directory.write("a.yml", "x")

    try writer.apply(
      WritePlan.making([.delete("a.yml")]),
      in: directory.url,
    )

    #expect(!exists("a.yml"))
  }

  @Test
  func `a file that is there is never overwritten, and nothing earlier in the plan is written`()
    throws
  {
    try directory.write("b.yml", "mine")

    let error = #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([
          .create("a.yml", "new"),
          .create("b.yml", "new"),
        ]),
        in: directory.url,
      )
    }

    #expect(error == .exists(path: "b.yml"))
    #expect(try text("b.yml") == "mine")
    #expect(!exists("a.yml"))
  }

  @Test(arguments: [FileChangeAction.replace, .delete])
  func `a file to replace or delete that is not there is refused`(
    action: FileChangeAction,
  ) throws {
    let error = #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([PlannedChange(action: action, path: "a.yml", text: "new")]),
        in: directory.url,
      )
    }

    #expect(error == .missing(path: "a.yml"))
  }

  @Test
  func `a folder in the place of a file to replace is refused`() throws {
    try directory.makeDirectory("a.yml")

    #expect(throws: PlanWritingError.missing(path: "a.yml")) {
      try writer.apply(
        WritePlan.making([.replace("a.yml", "new")]),
        in: directory.url,
      )
    }
  }

  @Test
  func `a file where a folder is needed is refused before anything is written`() throws {
    try directory.write("use-cases", "not a folder")

    let error = #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([
          .create("a.yml", "new"),
          .create("use-cases/example.yml", "new"),
        ]),
        in: directory.url,
      )
    }

    #expect(error == .obstructed(path: "use-cases", reason: "it is a file, not a folder"))
    #expect(!exists("a.yml"))
  }

  @Test
  func `a symlink where a folder is needed is refused, even to a folder`() throws {
    try directory.makeDirectory("real")
    try directory.symlink("use-cases", to: directory.location(of: "real").path)

    #expect(
      throws: PlanWritingError.obstructed(
        path: "use-cases",
        reason: "it is a symlink, not a folder",
      ),
    ) {
      try writer.apply(
        WritePlan.making([.create("use-cases/example.yml", "new")]),
        in: directory.url,
      )
    }
  }

  @Test
  func `a folder that cannot be written to is told with where and why`() throws {
    guard getuid() != 0 else {
      return
    }

    try directory.makeDirectory("locked")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: directory.location(of: "locked").path,
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: directory.location(of: "locked").path,
      )
    }

    let error = #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([.create("locked/a.yml", "new")]),
        in: directory.url,
      )
    }

    guard case let .unwritable(location, _)? = error else {
      Issue.record("unexpected error: \(String(describing: error))")
      return
    }

    #expect(location.contains("/locked/"))
  }

  @Test
  func `an empty plan writes nothing`() throws {
    try writer.apply(
      WritePlan(changes: []),
      in: directory.url,
    )

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
  }

  @Test
  func `a file made executable can be run by its owner, and one that is not cannot`() throws {
    try writer.apply(
      WritePlan.making([
        .createExecutable("hooks/pre-commit", "#!/bin/sh\n"),
        .create("hooks/notes.txt", "x"),
      ]),
      in: directory.url,
    )

    #expect(FileManager.default
      .isExecutableFile(atPath: directory.location(of: "hooks/pre-commit").path))
    #expect(!FileManager.default
      .isExecutableFile(atPath: directory.location(of: "hooks/notes.txt").path))
    #expect(try text("hooks/pre-commit") == "#!/bin/sh\n")
  }

  @Test
  func `an executable file never overwrites the one that is there`() throws {
    try directory.write("hooks/pre-commit", "mine")

    #expect(throws: PlanWritingError.exists(path: "hooks/pre-commit")) {
      try writer.apply(
        WritePlan.making([.createExecutable("hooks/pre-commit", "ours")]),
        in: directory.url,
      )
    }
    #expect(try text("hooks/pre-commit") == "mine")
  }
}
