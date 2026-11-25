import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A plan is all or nothing: a failure part way leaves every file, folder and name as it was.
struct AtomicPlanWriterRollbackTests {
  private let directory: TemporaryDirectory
  private let writer = AtomicPlanWriter()

  init() throws {
    directory = try TemporaryDirectory()
  }

  /// A folder nobody may change, with a file in it that a plan would take away.
  private func lockedFolder() throws {
    try directory.write("locked/b.yml", "kept")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: directory.location(of: "locked").path,
    )
  }

  private func unlock() {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: directory.location(of: "locked").path,
    )
  }

  /// Every name below the folder, hidden ones too, so a staged file left behind shows.
  private func names() -> [String] {
    let walker = FileManager.default.enumerator(atPath: directory.url.path)
    var found: [String] = []

    while let path = walker?.nextObject() as? String {
      found.append(path)
    }

    return found.sorted()
  }

  private func text(_ path: String) throws -> String {
    try String(
      contentsOf: directory.location(of: path),
      encoding: .utf8,
    )
  }

  @Test
  func `a change that fails after others were swapped in puts every one of them back`() throws {
    guard getuid() != 0 else {
      return
    }

    try directory.write("a.yml", "original")
    try lockedFolder()
    defer {
      unlock()
    }
    let before = names()

    #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([
          .create("new.yml", "new"),
          .replace("a.yml", "replaced"),
          .delete("locked/b.yml"),
        ]),
        in: directory.url,
      )
    }

    #expect(names() == before)
    #expect(try text("a.yml") == "original")
    #expect(try text("locked/b.yml") == "kept")
  }

  @Test
  func `a folder made for a new file is taken away again when the plan fails`() throws {
    guard getuid() != 0 else {
      return
    }

    try lockedFolder()
    defer {
      unlock()
    }
    let before = names()

    #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([
          .create("made/deeper/new.yml", "new"),
          .delete("locked/b.yml"),
        ]),
        in: directory.url,
      )
    }

    #expect(names() == before)
  }

  @Test
  func `a file that cannot be staged leaves nothing staged anywhere`() throws {
    guard getuid() != 0 else {
      return
    }

    try directory.write("a.yml", "original")
    try lockedFolder()
    defer {
      unlock()
    }
    let before = names()

    #expect(throws: PlanWritingError.self) {
      try writer.apply(
        WritePlan.making([
          .replace("a.yml", "replaced"),
          .replace("locked/b.yml", "replaced"),
        ]),
        in: directory.url,
      )
    }

    #expect(names() == before)
    #expect(try text("a.yml") == "original")
  }

  @Test
  func `plans for several folders are one all or nothing`() throws {
    guard getuid() != 0 else {
      return
    }

    let other = try TemporaryDirectory()
    try lockedFolder()
    defer {
      unlock()
    }

    #expect(throws: PlanWritingError.self) {
      try writer.apply(
        [
          FolderWrite(
            folder: other.url,
            plan: WritePlan.making([.create("hooks/pre-commit", "x")]),
          ),
          FolderWrite(
            folder: directory.url,
            plan: WritePlan.making([.delete("locked/b.yml")]),
          ),
        ],
        lockingIn: directory.url,
      )
    }

    #expect(!FileManager.default.fileExists(atPath: other.location(of: "hooks").path))
    #expect(try text("locked/b.yml") == "kept")
  }

  @Test
  func `a plan that goes through leaves no staged file and no backup`() throws {
    try directory.write("a.yml", "old")
    try directory.write("b.yml", "old")

    try writer.apply(
      WritePlan.making([
        .create("c/new.yml", "new"),
        .replace("a.yml", "new"),
        .delete("b.yml"),
      ]),
      in: directory.url,
    )

    #expect(names() == ["a.yml", "c", "c/new.yml"])
  }

  @Test
  func `a replaced file keeps its permissions`() throws {
    try directory.write("private.yml", "old")
    try directory.write("run.sh", "old")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: directory.location(of: "private.yml").path,
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o750],
      ofItemAtPath: directory.location(of: "run.sh").path,
    )

    try writer.apply(
      WritePlan.making([
        .replace("private.yml", "new"),
        .replace("run.sh", "new"),
      ]),
      in: directory.url,
    )

    let modes = try ["private.yml", "run.sh"].map { name in
      try #require(
        FileManager.default.attributesOfItem(atPath: directory.location(of: name).path)[
          .posixPermissions,
        ] as? Int,
      )
    }

    #expect(modes == [0o600, 0o750])
  }

  @Test
  func `a new file gets exactly the permissions of a file or of a hook, whatever the umask`()
    throws
  {
    let previous = umask(0o077)
    defer {
      umask(previous)
    }

    try writer.apply(
      WritePlan.making([
        .create("plain.yml", "x"),
        .createExecutable("hook", "x"),
      ]),
      in: directory.url,
    )

    let modes = try ["plain.yml", "hook"].map { name in
      try #require(
        FileManager.default.attributesOfItem(atPath: directory.location(of: name).path)[
          .posixPermissions,
        ] as? Int,
      )
    }

    #expect(modes == [0o644, 0o755])
  }
}
