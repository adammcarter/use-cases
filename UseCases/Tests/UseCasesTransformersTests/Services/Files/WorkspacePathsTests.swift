import Foundation
import Testing
@testable import UseCasesTransformers

struct WorkspacePathsTests {
  @Test
  func `an absolute path inside the workspace is relative to it`() throws {
    let folder = try TemporaryFolder()
    let paths = WorkspacePaths(codeRoot: folder.path)

    #expect(paths.relativePath(of: folder.absolute("Tests/A.swift")) == "Tests/A.swift")
  }

  @Test
  func `a relative path is read from the workspace root`() throws {
    let folder = try TemporaryFolder()
    let paths = WorkspacePaths(codeRoot: folder.path)

    #expect(paths.relativePath(of: "tests/a.py") == "tests/a.py")
    #expect(paths.relativePath(of: "tests/../tests/a.py") == "tests/a.py")
  }

  @Test(arguments: ["/elsewhere/a.py", "../a.py", "tests/../../a.py"])
  func `a path outside the workspace has no workspace spelling`(path: String) throws {
    let folder = try TemporaryFolder()

    #expect(WorkspacePaths(codeRoot: folder.path).relativePath(of: path) == nil)
  }

  @Test
  func `no path and the root itself have no workspace spelling`() throws {
    let folder = try TemporaryFolder()
    let paths = WorkspacePaths(codeRoot: folder.path)

    #expect(paths.relativePath(of: nil) == nil)
    #expect(paths.relativePath(of: folder.path) == nil)
  }

  @Test
  func `a root that does not exist still gives relative paths`() {
    let paths = WorkspacePaths(codeRoot: "/FROZEN")

    #expect(paths.relativePath(of: "/FROZEN/Tests/A.swift") == "Tests/A.swift")
  }

  @Test
  func `a path spelled through a symlink agrees with the real one`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "real/a.txt",
      "",
    )
    try FileManager.default.createSymbolicLink(
      atPath: folder.absolute("link"),
      withDestinationPath: folder.absolute("real"),
    )

    #expect(
      WorkspacePaths(codeRoot: folder.path).relativePath(of: folder.absolute("link/a.txt"))
        == "real/a.txt",
    )
  }

  @Test
  func `paths resolve against a folder unless they are absolute`() {
    let paths = WorkspacePaths(codeRoot: "/FROZEN")

    #expect(
      paths.resolve(
        "a.py",
        in: "web",
      ) == "/FROZEN/web/a.py",
    )
    #expect(paths.resolve(
      "/abs/a.py",
      in: "web",
    ) == "/abs/a.py")
    #expect(paths.resolve(
      "a.py",
      in: "/other",
    ) == "/other/a.py")
  }
}
