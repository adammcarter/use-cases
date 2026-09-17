import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// `NodeFile.rename` is `renameSync`: the file moves, and a failure carries
/// node's code and node's message naming both paths. `writeText`'s mode is
/// `writeFileSync`'s: it applies only when the file is created.
struct NodeFileTests {
  @Test
  func `creates a file with the mode asked for, and leaves an existing file's mode alone`() throws {
    let root = try TemporaryDirectory()
    let created = root.url.appendingPathComponent("created.pem").path
    let existing = try root.writeFile("existing.pem", contents: "old").path

    try NodeFile.writeText("new", atPath: created, mode: 0o600)
    try NodeFile.writeText("new", atPath: existing, mode: 0o600)

    let mode = { (path: String) in
      try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    }
    let createdMode = try mode(created)
    let existingMode = try mode(existing)
    #expect(createdMode == 0o600)
    #expect(existingMode == 0o644)
    #expect(try NodeFile.readText(atPath: existing) == "new")
  }

  @Test
  func `renames a file over an existing one`() throws {
    let root = try TemporaryDirectory()
    let source = try root.writeFile("source.tmp", contents: "new\n").path
    let destination = try root.writeFile("use-cases.yml", contents: "old\n").path

    try NodeFile.rename(from: source, to: destination)

    #expect(!FileManager.default.fileExists(atPath: source))
    #expect(try NodeFile.readText(atPath: destination) == "new\n")
  }

  @Test(arguments: [
    ("missing", "x", "ENOENT", "no such file or directory"),
    ("file", "no-directory/x", "ENOENT", "no such file or directory"),
    ("file", "directory", "EISDIR", "illegal operation on a directory"),
  ])
  func `fails with node's code and a message naming both paths`(
    source: String,
    destination: String,
    code: String,
    description: String,
  ) throws {
    let root = try TemporaryDirectory()
    try root.writeFile("file", contents: "x")
    try root.writeFile("directory/inner", contents: "y")
    let sourcePath = root.url.appendingPathComponent(source).path
    let destinationPath = root.url.appendingPathComponent(destination).path

    let error = #expect(throws: FileAccessError.self) {
      try NodeFile.rename(from: sourcePath, to: destinationPath)
    }

    #expect(error?.code == code)
    #expect(error?
      .message == "\(code): \(description), rename '\(sourcePath)' -> '\(destinationPath)'")
  }
}
