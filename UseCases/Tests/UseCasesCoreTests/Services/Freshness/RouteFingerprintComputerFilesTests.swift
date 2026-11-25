import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerFilesTests {
  private let fixture: FreshnessFixture

  init() throws {
    fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        resources: [FreshnessSamples.file("fixtures/users.json")],
      ),
    )
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    try fixture.write(
      "tests/t.swift",
      LinkSamples.marked("app.toggle#unit-tests.renders", "check()"),
    )
    try fixture.write("fixtures/users.json", "{}")
    try fixture.write("elsewhere.txt", "nothing links here")
  }

  @Test
  func `the digest of every linked and resource file is kept, sorted by path`() throws {
    let digests = try fixture.fingerprints().fileDigests
    let hasher = SHA256Hasher()

    #expect(digests.map(\.path) == ["fixtures/users.json", "src/app.swift", "tests/t.swift"])
    #expect(digests.first?.digest == hasher.sha256Hex(of: Array("{}".utf8)))
    #expect(
      digests.last?.digest == hasher.sha256Hex(
        of: Array(LinkSamples.marked("app.toggle#unit-tests.renders", "check()").utf8),
      ),
    )
  }

  @Test
  func `a file nothing links to is not among them`() throws {
    let digests = try fixture.fingerprints().fileDigests

    #expect(!digests.map(\.path).contains("elsewhere.txt"))
  }

  @Test
  func `each route knows the files it depends on, and a route without links has none`() throws {
    let routes = try fixture.fingerprints().routes
    let unit = try #require(routes.first { $0.route == "unit-tests" })
    let manual = try #require(routes.first { $0.route == "manual" })

    #expect(unit.files == ["fixtures/users.json", "src/app.swift", "tests/t.swift"])
    #expect(manual.files == ["src/app.swift"])
  }

  @Test
  func `the fingerprints do not change for being told their files`() throws {
    let first = try fixture.fingerprint()
    let second = try fixture.fingerprint()

    #expect(first == second)
  }
}
