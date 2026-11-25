import Foundation
import Testing
@testable import UseCasesCore

struct OwnedFileLocatorTests {
  private static let name = "use-case-groups.yml"

  private let fixture: WorkspaceFixture
  private let workspace: LoadedWorkspace

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("svc/use-cases.yml", YAMLSamples.child(prefix: "svc"))
    workspace = try fixture.loaded()
  }

  private func locate(
    using fileSystem: any FileSystemReading = LocalFileSystem(),
  ) throws(FileSystemError) -> OwnedFileLocation {
    let root = WorkspaceRoot(
      directory: workspace.root,
      settings: ScopeSettings(
        isRoot: true,
        useCasesDirectory: .root,
        excludes: [],
      ),
    )

    return try OwnedFileLocator(fileSystem: fileSystem).locate(
      Self.name,
      in: root,
      scopes: workspace.scopes,
      belowRoot: { file in
        Diagnostic(error: "below-root", in: file, message: "below")
      },
    )
  }

  @Test
  func `a root without the file finds nothing and says nothing`() throws {
    let location = try locate()

    #expect(location.entry == nil)
    #expect(location.diagnostics.isEmpty)
  }

  @Test
  func `the file is found by its exact name`() throws {
    try fixture.write(Self.name, "x")

    let location = try locate()

    #expect(location.entry?.name == Self.name)
    #expect(location.entry?.kind == .file)
    #expect(location.diagnostics.isEmpty)
  }

  @Test
  func `a folder with the name is found, for the loader to refuse`() throws {
    try fixture.directory.makeDirectory(Self.name)

    #expect(try locate().entry?.kind == .directory)
  }

  @Test(arguments: ["Use-Case-Groups.yml", "USE-CASE-GROUPS.YML", "use-case-Groups.yml"])
  func `a name that is the same only ignoring case is not the file, and is a problem`(
    spelling: String,
  ) throws {
    try fixture.write(spelling, "x")

    let location = try locate()

    #expect(location.entry == nil)
    #expect(location.diagnostics.map(\.description) == [
      "\(spelling): '\(spelling)' is not spelled \(Self.name), so it is not read; the file must "
        + "be named exactly \(Self.name), case and Unicode form included",
    ])
  }

  @Test(.enabled(if: TemporaryDirectory.allowsNamesDifferingInCase))
  func `a lookalike beside the real file is a problem and the real file is still found`() throws {
    try fixture.write(Self.name, "x")
    try fixture.write("Use-Case-Groups.yml", "y")

    let location = try locate()

    #expect(location.entry?.name == Self.name)
    #expect(location.diagnostics.count == 1)
  }

  @Test
  func `a folder spelled in another case is no lookalike`() throws {
    try fixture.directory.makeDirectory("Use-Case-Groups.yml")

    #expect(try locate().diagnostics.isEmpty)
  }

  @Test
  func `the file in a child scope is the problem the caller names, at its path`() throws {
    try fixture.write("svc/\(Self.name)", "x")

    let location = try locate()

    #expect(location.entry == nil)
    #expect(location.diagnostics.map(\.description) == ["svc/\(Self.name): below"])
  }

  @Test
  func `a lookalike in a child scope is a problem too`() throws {
    try fixture.write("svc/Use-Case-Groups.yml", "x")

    let location = try locate()

    #expect(location.diagnostics.map(\.description).first?.hasPrefix("svc/Use-Case-Groups.yml: ")
      == true)
    #expect(location.diagnostics.count == 1)
  }

  @Test
  func `a root that cannot be listed is a failure, not an absent file`() {
    #expect(throws: FileSystemError.self) {
      try locate(using: UnlistableFileSystem())
    }
  }
}
