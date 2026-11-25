import Testing
@testable import UseCasesCore

struct PromiseFingerprinterTests {
  private let fingerprinter = PromiseFingerprinter()

  /// The promise vector of `fingerprint_vectors.py`, section 89.9.
  private static let vectorPayload = [
    #"{"description":null,"id":"example.success","intent":"Demonstrate success.","#,
    #""out_of_scope":["Retries."],"scenarios":[{"given":[],"id":"success","#,
    #""then":["Success is visible."],"when":["Perform the action."]},"#,
    #"{"given":["The service is down."],"id":"failure","#,
    #""then":["A clear error is shown."],"when":["Perform the action."]}],"#,
    #""title":"Success","value_tier":"core"}"#,
  ].joined()

  private static let vectorFingerprint =
    "ba2fbe04bc7c271e32485c62b149f1727f6be53f313c587795cbb3d26f20f17a"

  private func scenario(
    _ identifier: String,
    given: [String],
    when: [String],
    then: [String],
  ) throws -> Scenario {
    try Scenario(
      identifier: ScenarioIdentifier(validating: identifier),
      given: given,
      when: when,
      then: then,
    )
  }

  private func vector(
    title: String = "Success",
    description: String? = nil,
    valueTier: ValueTier? = .core,
    intent: String? = "Demonstrate success.",
    outOfScope: [String] = ["Retries."],
  ) throws -> PromiseFingerprintInput {
    try PromiseFingerprintInput(
      useCase: UseCaseIdentifier(validating: "example.success"),
      title: title,
      description: description,
      valueTier: valueTier,
      intent: intent,
      scenarios: [
        scenario(
          "success",
          given: [],
          when: ["Perform the action."],
          then: ["Success is visible."],
        ),
        scenario(
          "failure",
          given: ["The service is down."],
          when: ["Perform the action."],
          then: ["A clear error is shown."],
        ),
      ],
      outOfScope: outOfScope,
    )
  }

  @Test
  func `the payload is the published bytes`() throws {
    let payload = try fingerprinter.payload(of: vector())

    #expect(payload.count == 361)
    #expect(payload.utf8Text == Self.vectorPayload)
  }

  @Test
  func `the fingerprint is the published digest, bare`() throws {
    #expect(try fingerprinter.fingerprint(of: vector()) == Self.vectorFingerprint)
  }

  @Test
  func `a draft with nothing but a title writes null text and empty lists`() throws {
    let input = try PromiseFingerprintInput(
      useCase: UseCaseIdentifier(validating: "app.draft"),
      title: "Draft",
      description: nil,
      valueTier: nil,
      intent: nil,
      scenarios: [],
      outOfScope: [],
    )

    let payload = try fingerprinter.payload(of: input)

    #expect(
      payload.utf8Text
        == #"{"description":null,"id":"app.draft","intent":null,"out_of_scope":[],"#
        + #""scenarios":[],"title":"Draft","value_tier":null}"#,
    )
  }

  @Test
  func `an absent description is not an empty one`() throws {
    let absent = try fingerprinter.fingerprint(of: vector(description: nil))
    let empty = try fingerprinter.fingerprint(of: vector(description: ""))

    #expect(absent != empty)
  }

  @Test
  func `changing the title changes the fingerprint`() throws {
    #expect(try fingerprinter.fingerprint(of: vector(title: "Other")) != Self.vectorFingerprint)
  }

  @Test
  func `adding a description changes the fingerprint`() throws {
    let changed = try fingerprinter.fingerprint(of: vector(description: "Words."))

    #expect(changed != Self.vectorFingerprint)
  }

  @Test
  func `changing the intent changes the fingerprint`() throws {
    let changed = try fingerprinter.fingerprint(of: vector(intent: "Another reason."))

    #expect(changed != Self.vectorFingerprint)
  }

  @Test
  func `changing out of scope changes the fingerprint`() throws {
    let changed = try fingerprinter.fingerprint(of: vector(outOfScope: ["Something else."]))

    #expect(changed != Self.vectorFingerprint)
  }

  @Test
  func `changing the value tier changes the fingerprint`() throws {
    let changed = try fingerprinter.fingerprint(of: vector(valueTier: .critical))

    #expect(changed != Self.vectorFingerprint)
  }

  @Test
  func `scenario and out of scope order is kept`() throws {
    let base = try vector(outOfScope: ["One.", "Two."])
    let swapped = try vector(outOfScope: ["Two.", "One."])
    let reversed = PromiseFingerprintInput(
      useCase: base.useCase,
      title: base.title,
      description: base.description,
      valueTier: base.valueTier,
      intent: base.intent,
      scenarios: base.scenarios.reversed(),
      outOfScope: base.outOfScope,
    )

    let original = try fingerprinter.fingerprint(of: base)
    let afterSwap = try fingerprinter.fingerprint(of: swapped)
    let afterReverse = try fingerprinter.fingerprint(of: reversed)

    #expect(original != afterSwap)
    #expect(original != afterReverse)
  }

  @Test
  func `the full id is part of the promise`() throws {
    let base = try vector()
    let moved = try PromiseFingerprintInput(
      useCase: UseCaseIdentifier(validating: "other.success"),
      title: base.title,
      description: base.description,
      valueTier: base.valueTier,
      intent: base.intent,
      scenarios: base.scenarios,
      outOfScope: base.outOfScope,
    )

    #expect(try fingerprinter.fingerprint(of: moved) != Self.vectorFingerprint)
  }

  @Test
  func `how a use case is proven is not part of the promise`() throws {
    let route = try ValidationRoute(
      identifier: RouteIdentifier(validating: "unit-tests"),
      type: .unit,
      covers: [ScenarioIdentifier(validating: "success")],
      gatesVerification: true,
      procedure: nil,
      bindings: [],
      resources: [],
    )
    let withRoute = try UseCaseDefinition(
      localIdentifier: IdentifierSegment(validating: "success"),
      title: "Success",
      description: nil,
      valueTier: .core,
      intent: "Demonstrate success.",
      outOfScope: ["Retries."],
      scenarios: vector().scenarios,
      routes: [route],
      bindings: [],
      approval: Approval(approver: "Sam", day: "2026-10-11", behaviour: "x"),
    )
    let identifier = try UseCaseIdentifier(validating: "example.success")

    let input = PromiseFingerprintInput(
      definition: withRoute,
      identifier: identifier,
    )

    #expect(try fingerprinter.fingerprint(of: input) == Self.vectorFingerprint)
  }

  @Test
  func `strings stay as written, so two Unicode forms of a title differ`() throws {
    let composed = try fingerprinter.fingerprint(of: vector(title: "caf\u{E9}"))
    let decomposed = try fingerprinter.fingerprint(of: vector(title: "cafe\u{301}"))

    #expect(composed != decomposed)
  }
}
