import Testing
@testable import UseCasesCore

/// The inputs the sample workspace should produce, built by hand from the pieces of the encoding
/// and never from the files under test, so the plumbing between the two is what a test compares.
enum ExpectedFingerprints {
  /// The input for a route of the sample use case.
  static func input(
    route: String,
    policy: FreshnessPolicy = FingerprintSamples.defaultPolicy,
    contributions: RouteContributions = RouteContributions(),
  ) throws -> RouteFingerprintInput {
    let isManual = route == "manual"

    return try input(
      RouteSpecification(
        useCase: FreshnessSamples.useCase,
        route: route,
        intent: "Readable at night.",
        scenarios: [
          scenario(
            "on-state",
            when: "x",
            then: "y",
          ),
        ],
        type: isManual ? .acceptance : .unit,
        procedure: isManual ? ["Check it."] : nil,
      ),
      policy: policy,
      contributions: contributions,
    )
  }

  /// The input for any route, from the words of its use case and the scenarios it covers.
  static func input(
    _ specification: RouteSpecification,
    policy: FreshnessPolicy = FingerprintSamples.defaultPolicy,
    contributions: RouteContributions = RouteContributions(),
  ) throws -> RouteFingerprintInput {
    try RouteFingerprintInput(
      policy: policy,
      useCase: UseCaseIdentifier(validating: specification.useCase),
      route: RouteIdentifier(validating: specification.route),
      intent: specification.intent,
      scenarios: specification.scenarios,
      type: specification.type,
      covers: specification.scenarios.map(\.identifier),
      gatesVerification: true,
      procedure: specification.procedure.map { steps in
        Procedure(
          setup: [],
          steps: steps,
          reset: [],
        )
      },
      implementationLinks: contributions.implementation,
      validationLinks: contributions.validation,
      resources: contributions.resources,
    )
  }

  /// A scenario with one step in each of `when` and `then`, and optionally a `given`.
  static func scenario(
    _ identifier: String,
    given: String? = nil,
    when: String,
    then: String,
  ) throws -> Scenario {
    try Scenario(
      identifier: ScenarioIdentifier(validating: identifier),
      given: given.map { step in
        [step]
      } ?? [],
      when: [when],
      then: [then],
    )
  }

  /// The fingerprint the encoder gives for `input`.
  static func fingerprint(of input: RouteFingerprintInput) throws -> String {
    try RouteFingerprinter().fingerprint(of: input)
  }

  /// A marker region written with `LinkSamples.marked`, in a file that holds nothing else: its
  /// span is the body's lines, after the start sentinel line.
  static func marker(
    _ target: String,
    body: String,
    in file: String,
    policy: FreshnessPolicy = FingerprintSamples.defaultPolicy,
  ) throws -> LinkContribution {
    let start = "// \(MarkerText.sentinel)\(target)\n".utf8.count
    let content = Array((body + "\n").utf8)
    let binding = try #require(target.split(separator: "#").last?.split(separator: ".").last)

    return try LinkContribution(
      binding: BindingIdentifier(validating: String(binding)),
      kind: .marker,
      regions: [
        LinkRegionContribution(
          locator: FingerprintLocator(
            file: workspacePath(file),
            startByte: start,
            endByte: start + content.count,
          ),
          content: ContentReferencer(policy: policy).reference(of: content),
        ),
      ],
    )
  }

  /// A manual binding of the whole of a file.
  static func manual(
    _ binding: String,
    file: String,
    text: String,
    policy: FreshnessPolicy = FingerprintSamples.defaultPolicy,
  ) throws -> LinkContribution {
    let bytes = Array(text.utf8)

    return try LinkContribution(
      binding: BindingIdentifier(validating: binding),
      kind: .manual,
      regions: [
        LinkRegionContribution(
          locator: FingerprintLocator(
            file: workspacePath(file),
            startByte: 0,
            endByte: bytes.count,
          ),
          content: ContentReferencer(policy: policy).reference(of: bytes),
        ),
      ],
    )
  }

  /// A resource file and its content.
  static func resource(
    _ file: String,
    text: String,
    policy: FreshnessPolicy = FingerprintSamples.defaultPolicy,
  ) throws -> ResourceContribution {
    try ResourceContribution(
      file: workspacePath(file),
      content: ContentReferencer(policy: policy).reference(of: Array(text.utf8)),
    )
  }
}
