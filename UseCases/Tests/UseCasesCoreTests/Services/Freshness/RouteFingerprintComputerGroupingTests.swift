import Testing
@testable import UseCasesCore

/// Links, scenarios and routes are grouped per use case and per route: two use cases share a
/// route id and a binding id, one scenario is covered by one route only, and a DRAFT has markers
/// of its own.
struct RouteFingerprintComputerGroupingTests {
  private let fixture: FreshnessFixture

  init() throws {
    fixture = try FreshnessFixture(definitions: FreshnessSamples.multipleUseCases())

    for marked in Self.files {
      try fixture.write(marked.file, LinkSamples.marked(marked.target, marked.body))
    }
  }

  private static let files = [
    MarkedFile(target: "app.alpha#core", file: "src/alpha.swift", body: "alpha()"),
    MarkedFile(target: "app.beta#core", file: "src/beta.swift", body: "beta()"),
    MarkedFile(target: "app.gamma#core", file: "src/gamma.swift", body: "gamma()"),
    MarkedFile(target: "app.alpha#unit.check", file: "tests/alpha_unit.swift", body: "alphaUnit()"),
    MarkedFile(target: "app.alpha#manual.look", file: "tests/alpha_manual.swift", body: "look()"),
    MarkedFile(target: "app.beta#unit.check", file: "tests/beta_unit.swift", body: "betaUnit()"),
    MarkedFile(target: "app.gamma#unit.check", file: "tests/gamma_unit.swift", body: "gammaUnit()"),
  ]

  private func marked(_ target: String) throws -> MarkedFile {
    try #require(
      Self.files.first { candidate in
        candidate.target == target
      },
    )
  }

  private func scenarios(_ names: [String]) throws -> [Scenario] {
    let known = try [
      "s1": ExpectedFingerprints.scenario("s1", when: "a1", then: "b1"),
      "s2": ExpectedFingerprints.scenario("s2", given: "g2", when: "a2", then: "b2"),
      "t1": ExpectedFingerprints.scenario("t1", when: "c1", then: "d1"),
    ]

    return try names.map { name in
      try #require(known[name])
    }
  }

  /// The fingerprint of a route built by hand: its use case's words, the scenarios it covers
  /// and the two marked files.
  private func expected(
    _ specification: RouteSpecification,
    implementation: String,
    validation: String,
  ) throws -> String {
    let implementationFile = try marked(implementation)
    let validationFile = try marked(validation)
    let contributions = try RouteContributions(
      implementation: [
        ExpectedFingerprints.marker(
          implementationFile.target,
          body: implementationFile.body,
          in: implementationFile.file,
        ),
      ],
      validation: [
        ExpectedFingerprints.marker(
          validationFile.target,
          body: validationFile.body,
          in: validationFile.file,
        ),
      ],
    )

    return try ExpectedFingerprints.fingerprint(
      of: ExpectedFingerprints.input(
        specification,
        contributions: contributions,
      ),
    )
  }

  @Test
  func `every route gets the fingerprint of its own hand-built input`() throws {
    let result = try fixture.fingerprints()

    let alphaUnit = try expected(
      RouteSpecification(
        useCase: "app.alpha",
        route: "unit",
        intent: "Alpha intent.",
        scenarios: scenarios(["s1", "s2"]),
        type: .unit,
        procedure: nil,
      ),
      implementation: "app.alpha#core",
      validation: "app.alpha#unit.check",
    )
    let alphaManual = try expected(
      RouteSpecification(
        useCase: "app.alpha",
        route: "manual",
        intent: "Alpha intent.",
        scenarios: scenarios(["s1"]),
        type: .acceptance,
        procedure: ["Check alpha."],
      ),
      implementation: "app.alpha#core",
      validation: "app.alpha#manual.look",
    )
    let betaUnit = try expected(
      RouteSpecification(
        useCase: "app.beta",
        route: "unit",
        intent: "Beta intent.",
        scenarios: scenarios(["t1"]),
        type: .integration,
        procedure: nil,
      ),
      implementation: "app.beta#core",
      validation: "app.beta#unit.check",
    )

    #expect(!result.isInvalid, "problems: \(result.problems)")
    #expect(result.fingerprint(useCase: "app.alpha", route: "unit") == alphaUnit)
    #expect(result.fingerprint(useCase: "app.alpha", route: "manual") == alphaManual)
    #expect(result.fingerprint(useCase: "app.beta", route: "unit") == betaUnit)
  }

  @Test
  func `the DRAFT has no fingerprint, and its markers reach no other use case`() throws {
    let result = try fixture.fingerprints()

    #expect(result.routes.map(\.useCase) == ["app.alpha", "app.alpha", "app.beta"])
    #expect(result.fingerprint(useCase: "app.gamma", route: "unit") == nil)
  }

  @Test
  func `a route that covers one scenario does not fingerprint another`() throws {
    let result = try fixture.fingerprints()
    let manual = try #require(result.fingerprint(useCase: "app.alpha", route: "manual"))
    let unit = try #require(result.fingerprint(useCase: "app.alpha", route: "unit"))

    #expect(manual != unit)

    try fixture.write("src/alpha.swift", LinkSamples.marked("app.alpha#core", "alpha()"))
    let again = try fixture.fingerprints()

    #expect(again.fingerprint(useCase: "app.alpha", route: "manual") == manual)
  }

  @Test
  func `changing a DRAFT's marker changes nothing`() throws {
    let before = try fixture.fingerprints()

    try fixture.write("src/gamma.swift", LinkSamples.marked("app.gamma#core", "changed()"))
    try fixture.write("tests/gamma_unit.swift", LinkSamples.marked("app.gamma#unit.check", "x()"))

    #expect(try fixture.fingerprints() == before)
  }

  @Test
  func `changing one use case's route marker changes only that route`() throws {
    let before = try fixture.fingerprints()

    try fixture.write("tests/beta_unit.swift", LinkSamples.marked("app.beta#unit.check", "new()"))
    let after = try fixture.fingerprints()

    #expect(
      after.fingerprint(useCase: "app.beta", route: "unit")
        != before.fingerprint(useCase: "app.beta", route: "unit"),
    )
    #expect(
      after.fingerprint(useCase: "app.alpha", route: "unit")
        == before.fingerprint(useCase: "app.alpha", route: "unit"),
    )
  }
}
