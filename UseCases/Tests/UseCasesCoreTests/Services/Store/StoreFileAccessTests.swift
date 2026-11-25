import Foundation
import Testing
@testable import UseCasesCore

struct StoreFileAccessTests {
  let directory: TemporaryDirectory
  let access = StoreFileAccess(
    fileSystem: LocalFileSystem(),
    json: JSONReader(),
  )

  init() throws {
    directory = try TemporaryDirectory()
  }

  private var root: StoreFile {
    StoreFile(workspace: directory.url).appending("folder")
  }

  @Test
  func `files below a folder are every non-folder, nested and sorted`() throws {
    try directory.write(".use-cases/folder/b.txt")
    try directory.write(".use-cases/folder/a/z.txt")
    try directory.write(".use-cases/folder/a/y/deep.txt")

    #expect(try access.files(below: root) == ["a/y/deep.txt", "a/z.txt", "b.txt"])
  }

  @Test
  func `a folder that is not there has no files`() throws {
    #expect(try access.files(below: root).isEmpty)
  }

  @Test
  func `empty folders hold no files`() throws {
    try directory.makeDirectory(".use-cases/folder/a/b")

    #expect(try access.files(below: root).isEmpty)
  }

  @Test
  func `a symlink is listed and never followed`() throws {
    try directory.write("target/inside.txt")
    try directory.symlink(".use-cases/folder/link", to: "../../target")

    #expect(try access.files(below: root) == ["link"])
  }

  @Test
  func `a file where the folder should be is corrupt`() throws {
    try directory.write(".use-cases/folder")

    #expect(throws: StoreProblem.corrupt(".use-cases/folder", "it is not a folder")) {
      try access.files(below: root)
    }
  }
}
