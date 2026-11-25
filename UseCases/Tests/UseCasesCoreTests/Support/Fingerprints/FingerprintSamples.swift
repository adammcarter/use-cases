import Testing
@testable import UseCasesCore

/// The inputs of the conformance vectors of chapter 11 §89.8, built from the real pieces: marker
/// regions come from the marker scanner, and every content reference from the real referencer.
enum FingerprintSamples {
  static let defaultPolicy = FreshnessPolicy(
    bindingIdentity: .content,
    ignoring: [.lineEndings],
  )

  static let strictPolicy = FreshnessPolicy(
    bindingIdentity: .contentAndLocator,
    ignoring: [.lineEndings],
  )

  /// The sample's one scenario.
  static func success() throws -> Scenario {
    try Scenario(
      identifier: ScenarioIdentifier(validating: "success"),
      given: [],
      when: ["Perform the action."],
      then: ["Success is visible."],
    )
  }

  static let referencer = ContentReferencer(policy: defaultPolicy)

  /// Vector A: a procedural route with no links.
  static func vectorA() throws -> RouteFingerprintInput {
    try input(
      policy: defaultPolicy,
      route: "manual",
      type: .acceptance,
      procedure: Procedure(
        setup: [],
        steps: ["Perform the action and observe success."],
        reset: [],
      ),
      contributions: RouteContributions(),
    )
  }

  /// Vector B: an automated route in content mode.
  static func vectorB() throws -> RouteFingerprintInput {
    try automated(
      policy: defaultPolicy,
      validationFile: validationFile(),
    )
  }

  /// Vector C: vector B under content-and-locator.
  static func vectorC() throws -> RouteFingerprintInput {
    try automated(
      policy: strictPolicy,
      validationFile: validationFile(),
    )
  }

  /// Vector D: a same-line pair with a nested pair, in content mode.
  static func vectorD() throws -> RouteFingerprintInput {
    let open = MarkerSamples.open
    let close = MarkerSamples.close
    let text = "x = /* \(open) */ f() + /* \(MarkerText.sentinel)example.other#inner */ g() "
      + "/* \(MarkerText.sentinel)end example.other#inner */ /* \(close) */\n"

    return try automated(
      policy: defaultPolicy,
      validationFile: text,
    )
  }

  /// Vector E: line mode with nested sentinel lines, under content-and-locator.
  static func vectorE() throws -> RouteFingerprintInput {
    let text = "// \(MarkerSamples.open)\nabc\n// \(MarkerText.sentinel)example.other#inner\ndef\n"
      + "// \(MarkerText.sentinel)end example.other#inner\n// \(MarkerSamples.close)\n"

    return try automated(
      policy: strictPolicy,
      validationFile: text,
    )
  }

  /// The validation file of vectors B and C.
  static func validationFile() -> String {
    "// \(MarkerSamples.open)\nabc\n// \(MarkerSamples.close)\n"
  }

  /// The route fields shared by every vector, around whatever links and resources it has.
  static func input(
    policy: FreshnessPolicy,
    route: String,
    type: ValidationType,
    procedure: Procedure?,
    contributions: RouteContributions,
  ) throws -> RouteFingerprintInput {
    try RouteFingerprintInput(
      policy: policy,
      useCase: UseCaseIdentifier(validating: "example.success"),
      route: RouteIdentifier(validating: route),
      intent: "Demonstrate success.",
      scenarios: [success()],
      type: type,
      covers: [ScenarioIdentifier(validating: "success")],
      gatesVerification: true,
      procedure: procedure,
      implementationLinks: contributions.implementation,
      validationLinks: contributions.validation,
      resources: contributions.resources,
    )
  }

  /// The automated route of vectors B to E: an empty whole-file manual implementation link, one
  /// marker validation link read from `validationFile`, and one resource.
  static func automated(
    policy: FreshnessPolicy,
    validationFile: String,
  ) throws -> RouteFingerprintInput {
    let referencer = ContentReferencer(policy: policy)

    return try input(
      policy: policy,
      route: "unit-tests",
      type: .unit,
      procedure: nil,
      contributions: RouteContributions(
        implementation: [
          wholeFileLink(referencer: referencer),
        ],
        validation: [
          markerLink(
            in: validationFile,
            referencer: referencer,
          ),
        ],
        resources: [
          ResourceContribution(
            file: workspacePath("fixtures/users.json"),
            content: referencer.reference(of: Array("{}".utf8)),
          ),
        ],
      ),
    )
  }

  /// The empty file `src/app.swift`, bound whole by a manual binding.
  static func wholeFileLink(referencer: any ContentReferencing) throws -> LinkContribution {
    let link = try ResolvedLink(
      source: .manual,
      identity: LinkIdentity(
        useCase: UseCaseIdentifier(validating: "example.success"),
        route: nil,
        binding: BindingIdentifier(validating: "implementation"),
      ),
      path: workspacePath("src/app.swift"),
      lines: 1 ... 1,
      span: 0 ..< 0,
      contentRanges: [],
    )

    return try contribution(
      of: link,
      bytes: [],
      referencer: referencer,
    )
  }

  /// The marker link the scanner finds in `text`.
  static func markerLink(
    in text: String,
    referencer: any ContentReferencing,
  ) throws -> LinkContribution {
    let bytes = Array(text.utf8)
    let scan = try MarkerSamples.scan(bytes: bytes)
    let region = try #require(scan.regions.first)
    let link = try ResolvedLink(
      source: .marker,
      identity: LinkIdentity(
        useCase: UseCaseIdentifier(validating: "example.success"),
        route: RouteIdentifier(validating: "unit-tests"),
        binding: BindingIdentifier(validating: "success"),
      ),
      path: workspacePath(MarkerSamples.file),
      lines: region.lines,
      span: region.byteRange,
      contentRanges: region.contentRanges,
    )

    return try contribution(
      of: link,
      bytes: bytes,
      referencer: referencer,
    )
  }

  /// A one-region binding read from a resolved link.
  static func contribution(
    of link: ResolvedLink,
    bytes: [UInt8],
    referencer: any ContentReferencing,
  ) throws -> LinkContribution {
    try LinkContribution(
      binding: BindingIdentifier(validating: link.binding),
      kind: LinkContributionKind(source: link.source),
      regions: [
        LinkRegionContribution(
          link: link,
          fileBytes: bytes,
          referencer: referencer,
        ),
      ],
    )
  }
}
