import Foundation
import Testing
@testable import UseCasesCore

struct CodeFileWalkerTests {
  private let fixture: FreshnessFixture

  init() throws {
    fixture = try FreshnessFixture(root: FreshnessSamples.root(exclude: ["vendor"]))
  }

  private func walk(
    _ workspace: LoadedWorkspace,
    using fileSystem: any FileSystemReading = LocalFileSystem(),
  ) -> CodeWalk {
    CodeFileWalker(fileSystem: fileSystem).walk(
      workspace,
      excluding: workspace.discoveryContext,
    )
  }

  @Test
  func `it names files and symlinks, and says which is which`() throws {
    try fixture.write("src/a.swift")
    try fixture.workspace.directory.symlink("link", to: "src/a.swift")

    let files = try walk(fixture.workspace.loaded()).files.sorted { lhs, rhs in
      lhs.path < rhs.path
    }

    #expect(files.map(\.path.text) == ["link", "src/a.swift"])
    #expect(files.map(\.kind) == [.symlink, .file])
  }

  @Test
  func `it leaves out what is excluded, owned or nested`() throws {
    try fixture.write("vendor/a.json")
    try fixture.write(".git/HEAD")
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n")
    try fixture.write("nested/use-cases.yml", "schema_version: 1\nroot: true\n")
    try fixture.write("nested/a.json")
    try fixture.write("kept.txt")

    #expect(try walk(fixture.workspace.loaded()).files.map(\.path.text) == ["kept.txt"])
  }

  @Test
  func `a pipe is warned about and never named`() throws {
    try fixture.workspace.directory.makeFIFO("pipe")

    let walked = try walk(fixture.workspace.loaded())

    #expect(walked.files.isEmpty)
    #expect(walked.diagnostics.map(\.severity) == [.warning])
  }

  @Test(.enabled(if: getuid() != 0, "permissions do not stop root"))
  func `a folder it cannot list is a problem`() throws {
    try fixture.write("locked/a.txt")
    let workspace = try fixture.workspace.loaded()
    let location = fixture.workspace.directory.location(of: "locked")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: location.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: location.path,
      )
    }

    #expect(walk(workspace).diagnostics.map(\.severity) == [.error])
  }
}
