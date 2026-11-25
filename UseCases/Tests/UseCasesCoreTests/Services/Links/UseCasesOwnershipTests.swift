import Testing
@testable import UseCasesCore

struct UseCasesOwnershipTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("child/use-cases.yml", YAMLSamples.child(prefix: "child"))
    try fixture.write("use-cases/toggle.yml", YAMLSamples.file(YAMLSamples.useCase()))
    try fixture.write("child/use-cases/more.yml", YAMLSamples.file(YAMLSamples.useCase("more")))
  }

  private func ownership() throws -> UseCasesOwnership {
    try UseCasesOwnership(fixture.loaded())
  }

  private func path(_ text: String) throws -> WorkspacePath {
    try WorkspacePath(validating: text)
  }

  @Test(
    arguments: [
      "use-cases.yml",
      "child/use-cases.yml",
      "use-cases/toggle.yml",
      "child/use-cases/more.yml",
      "use-case-groups.yml",
      "use-cases-bridge.yml",
    ],
  )
  func `a scope's configuration, a definition file and the root's own files belong to Use Cases`(
    file: String,
  ) throws {
    #expect(try ownership().owns(path(file)))
  }

  @Test(
    arguments: [
      "src/use-cases.yml",
      "child/use-case-groups.yml",
      "use-cases/notes.md",
      "README.md",
      "Use-Cases.yml",
    ],
  )
  func `anything else is code`(file: String) throws {
    #expect(try !ownership().owns(path(file)))
  }

  private func listing(_ names: [(String, FileEntryKind)]) -> [FileEntry] {
    names.map { name, kind in
      FileEntry(name: name, kind: kind)
    }
  }

  @Test
  func `a folder with a use-cases file that is no scope of this workspace is a nested workspace`()
    throws
  {
    let nested = listing([("use-cases.yml", .file), ("src", .directory)])

    #expect(try ownership().isNestedWorkspace(path("vendor/auth"), listing: nested))
  }

  @Test
  func `a scope of this workspace is not a nested workspace`() throws {
    let scope = listing([("use-cases.yml", .file)])

    #expect(try !ownership().isNestedWorkspace(path("child"), listing: scope))
  }

  @Test
  func `the root is never a nested workspace`() throws {
    #expect(try !ownership().isNestedWorkspace(.root, listing: listing([("use-cases.yml", .file)])))
  }

  @Test(
    arguments: [
      [("use-cases.yml", FileEntryKind.directory)],
      [("Use-Cases.yml", .file)],
      [("src", .directory)],
      [],
    ],
  )
  func `a folder without a use-cases file is not a nested workspace`(
    names: [(String, FileEntryKind)],
  ) throws {
    #expect(try !ownership().isNestedWorkspace(path("vendor/lib"), listing: listing(names)))
  }
}
