import Testing
@testable import UseCasesCore

/// What chapter 11 §89.4 says about ordering, deduplication and defaults of the route itself.
struct RouteFingerprinterNormalizationTests {
  private let fingerprinter = RouteFingerprinter()

  private func payload(_ input: RouteFingerprintInput) throws -> String {
    try fingerprinter.payload(of: input).utf8Text
  }

  @Test
  func `covers are deduplicated and sorted`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      scenarios: [FingerprintParts.scenario("b"), FingerprintParts.scenario("a")],
      covers: FingerprintParts.identifiers(["b", "a", "b"]),
    )

    #expect(try payload(input).contains(#""covers":["a","b"]"#))
  }

  @Test
  func `covered scenarios are sorted by id with exactly id given when and then`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      scenarios: [FingerprintParts.scenario("b"), FingerprintParts.scenario("a")],
      covers: FingerprintParts.identifiers(["b", "a"]),
    )

    #expect(
      try payload(input).contains(
        #""covered_scenarios":[{"given":[],"id":"a","then":["It is done."],"when":["Do it."]},"#
          + #"{"given":[],"id":"b","then":["It is done."],"when":["Do it."]}]"#,
      ),
    )
  }

  @Test
  func `reordering covers or scenarios does not change the fingerprint`() throws {
    let base = try FingerprintSamples.vectorA()
    let forward = try base.replacing(
      scenarios: [FingerprintParts.scenario("a"), FingerprintParts.scenario("b")],
      covers: FingerprintParts.identifiers(["a", "b"]),
    )
    let backward = try base.replacing(
      scenarios: [FingerprintParts.scenario("b"), FingerprintParts.scenario("a")],
      covers: FingerprintParts.identifiers(["b", "a"]),
    )

    #expect(try fingerprinter.fingerprint(of: forward) == fingerprinter.fingerprint(of: backward))
  }

  @Test
  func `scenario step order is kept`() throws {
    let base = try FingerprintSamples.vectorA()
    let first = try FingerprintParts.scenario("success", given: ["One.", "Two."])
    let second = try FingerprintParts.scenario("success", given: ["Two.", "One."])

    let one = try fingerprinter.fingerprint(of: base.replacing(scenarios: [first]))
    let other = try fingerprinter.fingerprint(of: base.replacing(scenarios: [second]))

    #expect(one != other)
  }

  @Test
  func `a scenario with no given is written with an empty one`() throws {
    let input = try FingerprintSamples.vectorA()

    #expect(try payload(input).contains(#"{"given":[],"id":"success""#))
  }

  @Test
  func `a covered scenario that is not supplied is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      covers: FingerprintParts.identifiers(["success", "other"]),
    )

    #expect(throws: FingerprintingError.coversWithoutScenario("other")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `a scenario supplied but not covered is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      scenarios: [FingerprintParts.scenario("success"), FingerprintParts.scenario("extra")],
    )

    #expect(throws: FingerprintingError.scenarioNotCovered("extra")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `the same scenario twice is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      scenarios: [FingerprintParts.scenario("success"), FingerprintParts.scenario("success")],
    )

    #expect(throws: FingerprintingError.duplicateScenario("success")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `a route cannot be fingerprinted without an intent`() throws {
    let input = try FingerprintSamples.vectorA().replacing(intent: .some(nil))

    #expect(throws: FingerprintingError.missingIntent) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test(
    arguments: [
      ([FreshnessNormalization](), "[]"),
      ([.lineEndings], #"["line-endings"]"#),
      ([.whitespace], #"["whitespace"]"#),
      ([.whitespace, .lineEndings, .whitespace], #"["line-endings","whitespace"]"#),
    ],
  )
  func `the ignore list is deduplicated with line endings first`(
    row: (rules: [FreshnessNormalization], written: String),
  ) throws {
    let policy = FreshnessPolicy(
      bindingIdentity: .content,
      ignoring: row.rules,
    )
    let input = try FingerprintSamples.vectorA().replacing(policy: policy)

    let expected = #""normalization":{"ignore":"# + row.written + "}"

    #expect(try payload(input).contains(expected))
  }

  @Test
  func `a policy change alone changes the fingerprint`() throws {
    let base = try FingerprintSamples.vectorA()
    let exact = FreshnessPolicy(
      bindingIdentity: .content,
      ignoring: [],
    )

    let standard = try fingerprinter.fingerprint(of: base)
    let changed = try fingerprinter.fingerprint(of: base.replacing(policy: exact))

    #expect(standard != changed)
  }

  @Test
  func `a custom type writes its kind and name`() throws {
    let base = try FingerprintSamples.vectorA()
    let input = try RouteFingerprintInput(
      policy: base.policy,
      useCase: base.useCase,
      route: base.route,
      intent: base.intent,
      scenarios: base.scenarios,
      type: .custom(name: IdentifierSegment(validating: "load-test")),
      covers: base.covers,
      gatesVerification: false,
      procedure: nil,
      implementationLinks: [],
      validationLinks: [],
      resources: [],
    )

    #expect(
      try payload(input).contains(
        #""route":{"covers":["success"],"gates_verification":false,"procedure":null,"#
          + #""type":{"kind":"custom","name":"load-test"}}"#,
      ),
    )
  }
}
