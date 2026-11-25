import Testing
@testable import UseCasesCore

struct LinkResolverTransformedTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
    try fixture.write("src/math.js", "one\ntwo\nthree\n")
  }

  private func transformed(
    _ links: [ResolvedLink],
    diagnostics: [Diagnostic] = [],
  ) -> TransformedLinks {
    TransformedLinks(
      findings: LinkFindings(
        links: links,
        diagnostics: diagnostics,
      ),
    )
  }

  private func resolve(_ transformed: TransformedLinks) throws -> LinkResolution {
    try LinkResolver().resolveLinks(
      in: fixture.loaded(),
      including: transformed,
    )
  }

  @Test
  func `no transformed links is what resolving without them gives`() throws {
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))

    let loaded = try fixture.loaded()

    #expect(
      LinkResolver().resolveLinks(in: loaded)
        == LinkResolver().resolveLinks(in: loaded, including: .none),
    )
  }

  @Test
  func `a transformer's links join the markers and manual bindings in the links order`() throws {
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))

    let resolution = try resolve(
      transformed([
        .sample(source: .transformer, binding: "zeta", file: "src/math.js"),
        .sample(source: .transformer, binding: "alpha", file: "src/math.js"),
      ]),
    )

    #expect(
      resolution.keys == [
        "app.toggle#alpha@src/math.js:1",
        "app.toggle#render@src/app.swift:2",
        "app.toggle#zeta@src/math.js:1",
      ],
    )
    #expect(resolution.links.map(\.source) == [.transformer, .marker, .transformer])
  }

  @Test
  func `what the transformers said is a warning in the same report order as the rest`() throws {
    try fixture.write("src/app.swift", "// \(MarkerText.sentinel)BAD\n")

    let resolution = try resolve(
      transformed(
        [],
        diagnostics: [.transformerSaid("read 2 tests", by: "tools/links")],
      ),
    )

    #expect(resolution.warningLines.count == 2)
    #expect(resolution.warningLines.first?
      .hasPrefix("src/app.swift:1: malformed marker id") == true)
    #expect(resolution.warningLines.last == "use-cases-bridge.yml: tools/links: read 2 tests")
    #expect(!resolution.isInvalid)
  }

  @Test
  func `a binding a marker and a transformer both name makes the workspace INVALID`() throws {
    try fixture.write(
      "tests/t.swift",
      LinkSamples.marked("app.toggle#manual.renders", "check()"),
    )

    let resolution = try resolve(
      transformed([
        .sample(source: .transformer, route: "manual", binding: "renders", file: "src/math.js"),
      ]),
    )

    #expect(resolution.isInvalid)
    #expect(resolution.links.isEmpty)
    #expect(resolution.problems(containing: "claimed by markers").count == 1)
    #expect(resolution.problems.first?.hasPrefix("use-cases/toggle.yml: ") == true)
  }

  @Test
  func `a binding a manual binding and a transformer both name makes the workspace INVALID`()
    throws
  {
    try fixture.writeUseCase(
      bindings: [LinkSamples.binding("config", file: "src/math.js")],
    )

    let resolution = try resolve(
      transformed([.sample(source: .transformer, binding: "config", file: "src/math.js")]),
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "claimed by a manual binding").count == 1)
  }

  @Test
  func `two transformers that return the same link share a key and make the workspace INVALID`()
    throws
  {
    let link = try ResolvedLink.sample(source: .transformer, binding: "x", file: "src/math.js")

    let resolution = try resolve(transformed([link, link]))

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "share the link key").count == 1)
  }

  @Test
  func `links of one use case and role over the same bytes warn, whichever sources they come from`()
    throws
  {
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))

    let resolution = try resolve(
      transformed([
        .sample(
          source: .transformer,
          binding: "again",
          file: "src/app.swift",
          lines: 1 ... 3,
          span: 25 ..< 45,
        ),
      ]),
    )

    #expect(!resolution.isInvalid)
    #expect(resolution.warnings(containing: "redundant overlapping links").count == 1)
  }
}
