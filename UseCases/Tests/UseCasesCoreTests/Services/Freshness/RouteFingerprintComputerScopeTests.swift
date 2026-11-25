import Testing
@testable import UseCasesCore

/// The policy is the root's, whatever child scopes exist (chapter 04: child scopes cannot
/// override it).
struct RouteFingerprintComputerScopeTests {
  private let policy = FreshnessPolicy(
    bindingIdentity: .contentAndLocator,
    ignoring: [.lineEndings, .whitespace],
  )

  private func fixtureWithChildScope() throws -> FreshnessFixture {
    let fixture = try FreshnessFixture(
      root: FreshnessSamples.root(
        bindingIdentity: "content-and-locator",
        ignore: "[line-endings, whitespace]",
      ),
    )
    try fixture.write("sub/use-cases.yml", YAMLSamples.child(prefix: "kid"))
    try fixture.write("sub/use-cases/toggle.yml", YAMLSamples.file(YAMLSamples.useCase("toggle")))
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#draw", "draw( )"))

    return fixture
  }

  @Test
  func `the root's policy applies, with a child scope present`() throws {
    let fixture = try fixtureWithChildScope()
    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        route: "unit-tests",
        policy: policy,
        contributions: RouteContributions(
          implementation: [
            ExpectedFingerprints.marker(
              "app.toggle#draw",
              body: "draw( )",
              in: "src/app.swift",
              policy: policy,
            ),
          ],
        ),
      ),
    )

    #expect(try fixture.fingerprint() == expected)
  }

  @Test
  func `a use case of a child scope is fingerprinted under the root's policy too`() throws {
    let fixture = try fixtureWithChildScope()
    let childRoute = try RouteSpecification(
      useCase: "app.kid.toggle",
      route: "manual",
      intent: "Readable at night.",
      scenarios: [ExpectedFingerprints.scenario("on-state", when: "x", then: "y")],
      type: .acceptance,
      procedure: ["Check it."],
    )
    let expected = try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        childRoute,
        policy: policy,
      ),
    )

    let result = try fixture.fingerprints()

    #expect(result.fingerprint(useCase: "app.kid.toggle", route: "manual") == expected)
  }
}
