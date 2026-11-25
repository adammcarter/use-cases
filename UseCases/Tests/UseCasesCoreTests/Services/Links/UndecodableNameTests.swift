import Testing
@testable import UseCasesCore

/// A name that is not valid UTF-8 is never silent, shown on every file system by listing one.
struct UndecodableNameTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
    try fixture.directory.makeDirectory("src")
  }

  @Test
  func `in the scanned tree it is skipped with a warning that names it escaped`() throws {
    let fileSystem = UndecodableNameFileSystem(in: fixture.directory.location(of: "src"))
    let workspace = try fixture.load(using: .reading(through: fileSystem))
    let resolver = LinkResolver(
      codeScanner: CodeScanner(
        fileSystem: fileSystem,
        markerScanner: MarkerScanner(),
      ),
      markerLinker: MarkerLinker(),
      bindingResolver: ManualBindingResolver(
        fileSystem: fileSystem,
        pathFinder: ExactPathFinder(fileSystem: fileSystem),
        rangeConverter: ManualRangeConverter(),
      ),
      conflictFinder: LinkConflictFinder(),
    )

    let resolution = resolver.resolveLinks(in: workspace)

    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: #"bad\xFF.js"#).count == 1)
    #expect(resolution.warnings(containing: "not valid UTF-8").count == 1)
  }

  @Test
  func `inside a use_cases_dir it makes the workspace INVALID`() throws {
    try fixture.directory.makeDirectory("use-cases")
    let fileSystem = UndecodableNameFileSystem(in: fixture.directory.location(of: "use-cases"))
    var problems: [String] = []

    do {
      _ = try fixture.load(using: .reading(through: fileSystem))
    } catch {
      problems = error.message.split(separator: "\n").map(String.init)
    }

    #expect(problems.count == 1)
    #expect(problems.first?.contains(#"bad\xFF.js"#) == true)
  }

  @Test
  func `a folder with such a name that holds a scope makes the workspace INVALID`() throws {
    let fileSystem = UndecodableNameFileSystem(
      in: fixture.directory.url,
      kind: .directory,
      holdsConfiguration: true,
    )
    var problems: [String] = []

    do {
      _ = try fixture.load(using: .reading(through: fileSystem))
    } catch {
      problems = error.message.split(separator: "\n").map(String.init)
    }

    #expect(problems.count == 1)
    #expect(problems.first?.contains(#"bad\xFF.js"#) == true)
    #expect(problems.first?.contains("use-cases.yml") == true)
  }

  @Test
  func `a folder with such a name that holds no scope is only a warning`() throws {
    let fileSystem = UndecodableNameFileSystem(
      in: fixture.directory.url,
      kind: .directory,
      holdsConfiguration: false,
    )

    let workspace = try fixture.load(using: .reading(through: fileSystem))

    #expect(workspace.warnings.map(\.code.text) == ["unspellable-name"])
    #expect(workspace.warnings.first?.message.contains(#"bad\xFF.js"#) == true)
  }
}
