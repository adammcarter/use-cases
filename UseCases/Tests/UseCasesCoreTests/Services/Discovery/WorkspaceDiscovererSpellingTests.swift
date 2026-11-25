import Testing
@testable import UseCasesCore

struct WorkspaceDiscovererSpellingTests {
  @Test(arguments: ["Use-Cases.yml", "use-cases.YML", "USE-CASES.YML"])
  func `a use-cases file spelled in another case is invalid, naming the file on disk`(
    name: String,
  ) throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.write("pkg/\(name)")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == ["."])
    #expect(discovery.diagnosticSummaries == ["pkg/\(name): configuration-spelled-differently"])
    #expect(discovery.diagnostics.first?.message.contains("'pkg/\(name)'") == true)
    #expect(!discovery.isValid)
  }

  @Test(
    .enabled(
      if: TemporaryDirectory.allowsNamesDifferingInCase,
      "this file system cannot hold two names that differ only in case",
    ),
  )
  func `a lookalike beside a real use-cases file is reported and the real one is still read`()
    throws
  {
    let fixture = try DiscoveryFixture()
    try fixture.scope("pkg")
    try fixture.directory.write("pkg/Use-Cases.yml")

    let discovery = try fixture.discover()

    #expect(discovery.scopeTree.scopes.map(\.directory.text) == [".", "pkg"])
    #expect(discovery
      .diagnosticSummaries == ["pkg/Use-Cases.yml: configuration-spelled-differently"])
    #expect(!discovery.isValid)
  }

  @Test
  func `a folder called like a use-cases file is not a spelling problem`() throws {
    let fixture = try DiscoveryFixture()
    try fixture.directory.makeDirectory("pkg/Use-Cases.yml")

    #expect(try fixture.discover().diagnostics.isEmpty)
  }

  @Test
  func `a wrong segment part-way along a use_cases_dir is named with the folders above it`()
    throws
  {
    let fixture = try DiscoveryFixture(
      rootConfiguration: "root: true\nuse_cases_dir: specs/Inner\n",
    )
    try fixture.directory.write("specs/inner/a.yml")

    let discovery = try fixture.discover()
    let message = try #require(discovery.diagnostics.first?.message)

    #expect(message.contains("on disk: \"specs/inner\""))
  }
}
