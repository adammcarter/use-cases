@testable import UseCasesCore

/// The collections of a route fingerprint input that vary between samples.
struct RouteContributions {
  var implementation: [LinkContribution] = []
  var validation: [LinkContribution] = []
  var resources: [ResourceContribution] = []
}

extension RouteFingerprintInput {
  /// The same input with some parts replaced.
  func replacing(
    policy: FreshnessPolicy? = nil,
    intent: String?? = nil,
    scenarios: [Scenario]? = nil,
    covers: [ScenarioIdentifier]? = nil,
    contributions: RouteContributions? = nil,
  ) -> RouteFingerprintInput {
    RouteFingerprintInput(
      policy: policy ?? self.policy,
      useCase: useCase,
      route: route,
      intent: intent ?? self.intent,
      scenarios: scenarios ?? self.scenarios,
      type: type,
      covers: covers ?? self.covers,
      gatesVerification: gatesVerification,
      procedure: procedure,
      implementationLinks: contributions?.implementation ?? implementationLinks,
      validationLinks: contributions?.validation ?? validationLinks,
      resources: contributions?.resources ?? resources,
    )
  }
}
