import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerOrderTests {
  private func busyFixture() throws -> FreshnessFixture {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("config", file: "config/auth.yml")],
        resources: [FreshnessSamples.glob("fixtures/**/*.json")],
      ),
    )
    try fixture.write("config/auth.yml", "a: 1\n")
    try fixture.write("src/b.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    try fixture.write("src/a.swift", LinkSamples.marked("app.toggle#draw", "fade()"))
    try fixture.write("tests/c.swift", LinkSamples.marked("app.toggle#unit-tests.t", "x"))

    for name in ["z", "y", "x", "w"] {
      try writeFixtures(named: name, in: fixture)
    }

    return fixture
  }

  private func writeFixtures(
    named name: String,
    in fixture: FreshnessFixture,
  ) throws {
    try fixture.write("fixtures/" + name + ".json", "{\"" + name + "\":1}")
    try fixture.write("fixtures/deep/" + name + ".json", "{\"" + name + "\":2}")
  }

  @Test
  func `the same workspace gives the same fingerprints twice`() throws {
    let fixture = try busyFixture()

    let first = try fixture.fingerprints()
    let second = try fixture.fingerprints()

    #expect(!first.isInvalid)
    #expect(first == second)
  }

  @Test
  func `the same files in another workspace give the same fingerprints`() throws {
    #expect(try busyFixture().fingerprints() == busyFixture().fingerprints())
  }

  @Test
  func `fingerprints do not depend on the order a file system lists names in`() throws {
    let fixture = try busyFixture()
    let reversed = ReversedListingFileSystem()
    let resolver = LinkResolver(
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
    )

    let forward = try fixture.fingerprints()
    let backward = try fixture.fingerprints(
      using: RouteFingerprintComputer(fileSystem: reversed),
      resolver: resolver,
    )

    #expect(!forward.isInvalid)
    #expect(forward == backward)
  }
}
