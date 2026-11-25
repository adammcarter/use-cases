extension UseCaseDefinition {
  /// READY when fully written, otherwise DRAFT with what is missing (chapter 02 "READY").
  ///
  /// READY needs a value tier, an intent, at least one scenario, at least one validation route,
  /// and every scenario covered by at least one gating route. Links are never needed. A
  /// definition that has already passed ``UseCaseChecking`` is the one to ask.
  var authoredState: AuthoredState {
    var missing: [ReadinessGap] = []

    if valueTier == nil {
      missing.append(.valueTier)
    }

    if intent == nil {
      missing.append(.intent)
    }

    if scenarios.isEmpty {
      missing.append(.scenarios)
    }

    if routes.isEmpty {
      missing.append(.validation)
    }

    for scenario in scenarios where !isCoveredByGatingRoute(scenario.identifier) {
      missing.append(.uncoveredScenario(scenario.identifier))
    }

    return missing.isEmpty ? .ready : .draft(missing: missing)
  }

  private func isCoveredByGatingRoute(_ identifier: ScenarioIdentifier) -> Bool {
    routes.contains { route in
      route.gatesVerification && route.covers.contains(identifier)
    }
  }
}
