import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// `NodeFile.rename` is `renameSync`: the file moves, and a failure carries
/// node's code and node's message naming both paths.
struct NodeFileTests {
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
