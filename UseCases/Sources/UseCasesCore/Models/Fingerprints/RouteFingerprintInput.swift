/// Everything a route fingerprint is made of (chapter 11 §89.4), in the shapes the core already
/// holds. Orders that mean nothing (covers, scenarios, links, regions, resources) may be given in
/// any order: the fingerprinter sorts them.
struct RouteFingerprintInput: Sendable {
  let policy: FreshnessPolicy
  let useCase: UseCaseIdentifier
  let route: RouteIdentifier

  /// The use case's intent. A route cannot be fingerprinted without one.
  let intent: String?

  /// The scenarios the route covers, each once.
  let scenarios: [Scenario]
  let type: ValidationType
  let covers: [ScenarioIdentifier]
  let gatesVerification: Bool
  let procedure: Procedure?

  /// One entry per binding of the use case.
  let implementationLinks: [LinkContribution]

  /// One entry per binding of this route.
  let validationLinks: [LinkContribution]
  let resources: [ResourceContribution]
}
