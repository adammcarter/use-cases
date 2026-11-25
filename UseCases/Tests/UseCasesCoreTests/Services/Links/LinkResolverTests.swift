import Foundation
import Testing
@testable import UseCasesCore

struct LinkResolverTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  @Test
  func `a workspace with no links and no code resolves to nothing`() throws {
    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warningLines.isEmpty)
    #expect(!resolution.isInvalid)
  }

  @Test
  func `markers and manual bindings come together in the order of the links document`() throws {
    try fixture.writeUseCase(
      bindings: [LinkSamples.binding("config", file: "config/auth.yml")],
      routeBindings: [LinkSamples.binding("helper", file: "tests/helper.swift")],
    )
    try fixture.write("config/auth.yml", "a: 1\n")
    try fixture.write("tests/helper.swift", "x\n")
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))
    try fixture.write(
      "tests/t.swift",
      LinkSamples.marked("app.toggle#manual.renders", "check()"),
    )

    let resolution = try fixture.resolved()

    #expect(
      resolution.keys == [
        "app.toggle#config@config/auth.yml:1",
        "app.toggle#render@src/app.swift:2",
        "app.toggle#manual.helper@tests/helper.swift:1",
        "app.toggle#manual.renders@tests/t.swift:2",
      ],
    )
    #expect(resolution.links.map(\.source) == [.manual, .marker, .manual, .marker])
  }

  @Test
  func `the start line orders as a number`() throws {
    try fixture.writeUseCase()
    let region = LinkSamples.marked("app.toggle#again", "x")
    try fixture.write(
      "src/x.js",
      region + "\n\n" + region + String(repeating: "\n", count: 4) + region,
    )
    try fixture.write("src/y.js", region + String(repeating: "\n", count: 8) + region)

    let resolution = try fixture.resolved()

    #expect(
      resolution.links.map(\.place) == [
        "src/x.js:2", "src/x.js:7", "src/x.js:14", "src/y.js:2", "src/y.js:13",
      ],
    )
  }

  @Test
  func `diagnostics order by path, then line as a number, then code`() throws {
    let lines = String(repeating: "\n", count: 8) + "# @use-case:BAD\n# @use-case:BAD\n"
    try fixture.write("src/x.py", lines)
    try fixture.write("src/a.py", String(repeating: "\n", count: 19) + "# @use-case:BAD\n")

    let warnings = try fixture.resolved()
      .warnings(containing: "malformed")
      .map(\.beforeFirstColonAndSpace)

    #expect(warnings == ["src/a.py:20", "src/x.py:9", "src/x.py:10"])
  }

  @Test
  func `problems and warnings are kept apart, and the links are withheld while any problem stands`()
    throws
  {
    try fixture.writeUseCase(bindings: [LinkSamples.binding("x", file: "nope.swift")])
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))
    try fixture.write("src/other.swift", "// @use-case:Bad_ID\n")

    let resolution = try fixture.resolved()

    #expect(resolution.isInvalid)
    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.count == 1)
    #expect(resolution.warningLines.count == 1)
  }

  @Test
  func `every problem found is reported, not only the first`() throws {
    try fixture.writeUseCase(
      bindings: [
        LinkSamples.binding("one", file: "missing/one.swift"),
        LinkSamples.binding("two", file: "missing/two.swift"),
      ],
    )
    try fixture.write("src/a.swift", "// @use-case:app.toggle#x\n")
    try fixture.write("src/b.swift", "// @use-case:end app.toggle#y\n")

    #expect(try fixture.resolved().problems.count == 4)
  }

  @Test
  func `the warnings of the load come with the warnings of the links`() throws {
    try fixture.write("bad\nfolder/code.swift", "x\n")
    try fixture.write("src/other.swift", "// @use-case:Bad_ID\n")

    let resolution = try fixture.resolved()

    #expect(resolution.warningLines.count == 2)
    #expect(resolution.warnings(containing: "malformed marker id").count == 1)
    #expect(resolution.warnings(containing: "no workspace path can spell").count == 1)
  }

  @Test
  func `the same workspace resolves to the same answer however a file system orders its listings`()
    throws
  {
    try fixture.writeUseCase(bindings: [LinkSamples.binding("config", file: "config/auth.yml")])
    try fixture.write("config/auth.yml", "a: 1\n")
    let region = LinkSamples.marked("app.toggle#render", "draw()")
    try fixture.write("src/b.swift", region)
    try fixture.write("src/a.swift", region + "// @use-case:Bad_ID\n")
    try fixture.write("tests/c.swift", LinkSamples.marked("app.toggle#manual.t", "x"))
    let workspace = try fixture.loaded()
    let reversed = ReversedListingFileSystem()

    let forward = LinkResolver().resolveLinks(in: workspace)
    let backward = LinkResolver(
      codeScanner: CodeScanner(
        fileSystem: reversed,
        markerScanner: MarkerScanner(),
      ),
      markerLinker: MarkerLinker(),
      bindingResolver: ManualBindingResolver(
        fileSystem: reversed,
        pathFinder: ExactPathFinder(fileSystem: reversed),
        rangeConverter: ManualRangeConverter(),
      ),
      conflictFinder: LinkConflictFinder(),
    ).resolveLinks(in: workspace)

    #expect(forward == backward)
    #expect(forward.links.count == 4)
  }

  @Test
  func `a YAML binding of kind marker is refused by loading, saying it needs no entry`() throws {
    try fixture.write(
      "use-cases/toggle.yml",
      YAMLSamples.file(
        YAMLSamples.useCase(
          "toggle",
          extra: "    bindings:\n      - id: x\n        kind: marker\n",
        ),
      ),
    )

    let problems = fixture.problems()

    let elsewhere = problems.filter { line in
      !line.hasPrefix("use-cases/toggle.yml: ")
    }

    #expect(problems.count == 1)
    #expect(elsewhere.isEmpty)
    #expect(problems.first?.contains("need no entry") == true)
  }
}
