import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerWarningTests {
  private func fixture(
    resources: [String],
    isReady: Bool = true,
    exclude: [String] = ["vendor"],
  ) throws -> FreshnessFixture {
    try FreshnessFixture(
      root: FreshnessSamples.root(exclude: exclude),
      definitions: FreshnessSamples.definitions(
        isReady: isReady,
        resources: resources,
      ),
    )
  }

  @Test
  func `an explicit resource in a folder discovery.exclude leaves out is valid and warns`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("vendor/a.json")])
    try fixture.write("vendor/a.json", "{}")

    let result = try fixture.fingerprints()

    #expect(!result.isInvalid)
    #expect(result.routes.count == 2)
    #expect(
      result.warningLines == [
        "vendor/a.json:1: the resource points at excluded content: route 'unit-tests' of use "
          + "case 'app.toggle' names this file, which discovery.exclude 'vendor' leaves out "
          + "of the scan",
      ],
    )
  }

  @Test
  func `a built-in exclusion warns the same way`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file(".git/HEAD")])
    try fixture.write(".git/HEAD", "ref: x\n")

    let result = try fixture.fingerprints()

    #expect(!result.isInvalid)
    #expect(result.warningLines.count == 1)
    #expect(result.warningLines.first?.hasPrefix(".git/HEAD:1: the resource points at") == true)
    #expect(result.warningLines.first?.contains("the built-in exclusion '**/.git/**'") == true)
  }

  @Test
  func `the warning does not change the fingerprint`() throws {
    let excluded = try fixture(resources: [FreshnessSamples.file("vendor/a.json")])
    let plain = try fixture(
      resources: [FreshnessSamples.file("vendor/a.json")],
      exclude: [],
    )
    try excluded.write("vendor/a.json", "{}")
    try plain.write("vendor/a.json", "{}")

    #expect(try plain.fingerprints().warningLines.isEmpty)
    #expect(try excluded.fingerprint() == plain.fingerprint())
  }

  @Test
  func `a resource outside every exclusion does not warn`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("fixtures/a.json")])
    try fixture.write("fixtures/a.json", "{}")

    #expect(try fixture.fingerprints().warningLines.isEmpty)
  }

  @Test
  func `a glob never warns`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.glob("**/*.json")])
    try fixture.write("fixtures/a.json", "{}")
    try fixture.write("vendor/a.json", "{}")

    #expect(try fixture.fingerprints().warningLines.isEmpty)
  }

  @Test
  func `the warning is given even when the workspace is INVALID`() throws {
    let fixture = try fixture(
      resources: [
        FreshnessSamples.file("vendor/a.json"),
        FreshnessSamples.file("missing.json"),
      ],
    )
    try fixture.write("vendor/a.json", "{}")

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.warningLines.count == 1)
  }

  @Test
  func `a DRAFT use case's resources warn too`() throws {
    let fixture = try fixture(
      resources: [FreshnessSamples.file("vendor/a.json")],
      isReady: false,
    )
    try fixture.write("vendor/a.json", "{}")

    let result = try fixture.fingerprints()

    #expect(result.routes.isEmpty)
    #expect(result.warningLines.count == 1)
  }

  @Test
  func `a missing file in an excluded folder is a problem, not a warning`() throws {
    let fixture = try fixture(resources: [FreshnessSamples.file("vendor/nope.json")])

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.warningLines.isEmpty)
  }
}
