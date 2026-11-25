extension RouteFingerprintInput {
  /// The input for one route of a use case that is READY, around the links and resources the
  /// run resolved for it. The scenarios are those the route covers.
  init(
    useCase: LoadedUseCase,
    route: ValidationRoute,
    policy: FreshnessPolicy,
    implementationLinks: [LinkContribution],
    validationLinks: [LinkContribution],
    resources: [ResourceContribution],
  ) {
    self.init(
      policy: policy,
      useCase: useCase.identifier,
      route: route.identifier,
      intent: useCase.definition.intent,
      scenarios: useCase.definition.scenarios.filter { scenario in
        route.covers.contains(scenario.identifier)
      },
      type: route.type,
      covers: route.covers,
      gatesVerification: route.gatesVerification,
      procedure: route.procedure,
      implementationLinks: implementationLinks,
      validationLinks: validationLinks,
      resources: resources,
    )
  }
}
