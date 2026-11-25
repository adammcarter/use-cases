import Foundation
import Testing
@testable import UseCasesCore

struct ExactPathFinderTests {
  private let directory: TemporaryDirectory
  private let finder = ExactPathFinder(fileSystem: LocalFileSystem())

  init() throws {
    directory = try TemporaryDirectory()
    try directory.write("src/app/main.swift", "x")
    try directory.write("top.txt", "x")
    try directory.makeDirectory("empty")
    try directory.symlink("alias", to: "src")
    try directory.symlink("top-link", to: "top.txt")
  }

  private func find(_ path: String) throws -> FileEntryKind {
    var listings = FolderListings()

    return try finder.find(
      WorkspacePath(validating: path),
      in: .excludingNothing(in: directory),
      listings: &listings,
    )
  }

  @Test(
    arguments: [
      ("src/app/main.swift", FileEntryKind.file),
      ("top.txt", .file),
      ("src/app", .directory),
      ("empty", .directory),
      ("top-link", .symlink),
    ],
  )
  func `a path spelled as it is on disk is found, and told what it is`(
    case example: (path: String, kind: FileEntryKind),
  ) throws {
    #expect(try find(example.path) == example.kind)
  }

  @Test(arguments: ["nope.txt", "src/nope.swift", "nope/main.swift", "empty/inside.txt"])
  func `a path with nothing at it is missing`(path: String) {
    #expect(throws: ExactPathError.missing) {
      try find(path)
    }
  }

  @Test
  func `a file where a folder should be is missing`() {
    #expect(throws: ExactPathError.missing) {
      try find("top.txt/inside")
    }
  }

  @Test
  func `a symlink on the way is never followed`() throws {
    let link = try WorkspacePath(validating: "alias")

    #expect(throws: ExactPathError.behindSymlink(link)) {
      try find("alias/app/main.swift")
    }
  }

  @Test
  func `another case is a different spelling, whatever the file system says`() {
    #expect(throws: ExactPathError.spelledDifferently(written: "Src", onDisk: "src")) {
      try find("Src/app/main.swift")
    }
    #expect(throws: ExactPathError.spelledDifferently(
      written: "MAIN.swift",
      onDisk: "main.swift",
    )) {
      try find("src/app/MAIN.swift")
    }
  }

  @Test
  func `another Unicode form is a different spelling`() throws {
    let composed = "caf\u{E9}.js"
    let decomposed = "cafe\u{301}.js"
    try directory.write("src/\(composed)", "x")
    let listed = try LocalFileSystem().entries(in: directory.location(of: "src")).map(\.name)

    let storedDecomposed = listed.filter { name in
      name.isExactlyEqual(to: decomposed)
    }

    guard storedDecomposed.isEmpty else {
      return
    }

    #expect(throws: ExactPathError.spelledDifferently(written: decomposed, onDisk: composed)) {
      try find("src/\(decomposed)")
    }
  }

  @Test(.enabled(if: getuid() != 0))
  func `a folder that cannot be listed is named`() throws {
    let locked = directory.location(of: "src/app")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    var listings = FolderListings()
    var caught: ExactPathError?
    let path = try WorkspacePath(validating: "src/app/main.swift")

    do {
      _ = try finder.find(
        path,
        in: .excludingNothing(in: directory),
        listings: &listings,
      )
    } catch {
      caught = error
    }

    guard case let .unreadableFolder(folder, _)? = caught else {
      Issue.record("expected an unreadable folder, got \(String(describing: caught))")
      return
    }

    #expect(folder.text == "src/app")
  }
}
