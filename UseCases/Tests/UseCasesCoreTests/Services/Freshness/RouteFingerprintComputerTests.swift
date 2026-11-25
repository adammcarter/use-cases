import Foundation
import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerTests {
  @Test
  func `a route with no links or resources gets the fingerprint of the hand-built input`() throws {
    let fixture = try FreshnessFixture()

    for route in ["manual", "unit-tests"] {
      let expected = try ExpectedFingerprints.fingerprint(
        of: ExpectedFingerprints.input(route: route),
      )

      #expect(try fixture.fingerprint(of: route) == expected)
    }
  }

  @Test
  func `links and a resource reach the fingerprint through the encoder`() throws {
    let fixture = try FreshnessFixture(
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

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          implementation: [
            ExpectedFingerprints.marker("app.toggle#draw", body: "draw()", in: "src/app.swift"),
          ],
          validation: [
            ExpectedFingerprints.marker(
              "app.toggle#unit-tests.renders",
              body: "check()",
              in: "tests/t.swift",
            ),
          ],
          resources: [
            ExpectedFingerprints.resource("fixtures/users.json", text: "{}"),
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `content-and-locator reaches the fingerprint with locators and the source kind`() throws {
    let fixture = try FreshnessFixture(
      root: FreshnessSamples.root(bindingIdentity: "content-and-locator"),
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("config", file: "config/auth.yml")],
      ),
    )
    try fixture.write("config/auth.yml", "a: 1\n")
    try fixture.write("src/app.swift", "// pad\n" + LinkSamples.marked("app.toggle#draw", "draw()"))

    let policy = FingerprintSamples.strictPolicy
    let marker = try ExpectedFingerprints.marker(
      "app.toggle#draw",
      body: "draw()",
      in: "src/app.swift",
      policy: policy,
    )
    let shifted = try shift(marker, by: "// pad\n".utf8.count)
    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        policy: policy,
        contributions: RouteContributions(
          implementation: [
            ExpectedFingerprints.manual("config", file: "config/auth.yml", text: "a: 1\n"),
            shifted,
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `implementation links are shared by every route and validation links belong to one`()
    throws
  {
    let quiet = try FreshnessFixture()
    let implementation = try FreshnessFixture()
    let tests = try FreshnessFixture()
    try implementation.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw()"))
    try tests.write("t/t.swift", LinkSamples.marked("app.toggle#unit-tests.renders", "check()"))

    #expect(try implementation.fingerprint(of: "manual") != quiet.fingerprint(of: "manual"))
    #expect(try implementation.fingerprint(of: "unit-tests") != quiet.fingerprint(of: "unit-tests"))
    #expect(try tests.fingerprint(of: "unit-tests") != quiet.fingerprint(of: "unit-tests"))
    #expect(try tests.fingerprint(of: "manual") == quiet.fingerprint(of: "manual"))
  }

  @Test
  func `every route of a READY use case has a fingerprint, in the order written`() throws {
    let result = try FreshnessFixture().fingerprints()

    #expect(!result.isInvalid)
    #expect(result.routes.map(\.route) == ["manual", "unit-tests"])
    #expect(result.routes.allSatisfy { route in
      route.useCase == "app.toggle" && route.fingerprint.hasPrefix("uc-route-v1-sha256:")
    })
  }

  @Test
  func `a DRAFT use case has no fingerprint`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(isReady: false),
    )

    let result = try fixture.fingerprints()

    #expect(!result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(result.fingerprint(useCase: "app.toggle", route: "manual") == nil)
  }

  @Test
  func `an unknown route has no fingerprint`() throws {
    let result = try FreshnessFixture().fingerprints()

    #expect(result.fingerprint(useCase: "app.toggle", route: "nope") == nil)
    #expect(result.fingerprint(useCase: "app.other", route: "manual") == nil)
  }

  @Test
  func `a manual binding of a symlink is fingerprinted as the text the symlink holds`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(
        bindings: [LinkSamples.binding("link", file: "src/current")],
      ),
    )
    try fixture.workspace.directory.symlink(
      "src/current",
      to: "releases/v1",
    )

    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        contributions: RouteContributions(
          implementation: [
            ExpectedFingerprints.manual("link", file: "src/current", text: "releases/v1"),
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  /// The same marker with its locator moved down by `bytes`.
  private func shift(
    _ contribution: LinkContribution,
    by bytes: Int,
  ) throws -> LinkContribution {
    let region = try #require(contribution.regions.first)

    return LinkContribution(
      binding: contribution.binding,
      kind: contribution.kind,
      regions: [
        LinkRegionContribution(
          locator: FingerprintLocator(
            file: region.locator.file,
            startByte: region.locator.startByte + bytes,
            endByte: region.locator.endByte + bytes,
          ),
          content: region.content,
        ),
      ],
    )
  }
}
