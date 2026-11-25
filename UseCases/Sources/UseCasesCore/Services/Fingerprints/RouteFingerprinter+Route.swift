extension RouteFingerprinter {
  /// The policy in the order and spelling the chapter fixes: each rule once, line endings before
  /// whitespace (§89.4).
  func policyValue(of policy: FreshnessPolicy) -> CanonicalValue {
    let ignored = FreshnessNormalization.allCases.filter { rule in
      policy.ignoring.contains(rule)
    }

    return .members([
      "binding_identity": .string(policy.bindingIdentity.rawValue),
      "normalization": .members([
        "ignore": .strings(
          ignored.map { rule in
            rule.rawValue
          },
        ),
      ]),
    ])
  }

  /// The covered scenarios sorted by id, which must be exactly the ids the route covers.
  func scenariosValue(
    of scenarios: [Scenario],
    covers: [ScenarioIdentifier],
  ) throws(FingerprintingError) -> CanonicalValue {
    let sorted = scenarios.sorted { lhs, rhs in
      lhs.identifier.text.precedesExactly(rhs.identifier.text)
    }

    for (index, scenario) in sorted.enumerated() where index > 0 {
      if scenario.identifier.text.isExactlyEqual(to: sorted[index - 1].identifier.text) {
        throw .duplicateScenario(scenario.identifier.text)
      }
    }

    let supplied = sorted.map { scenario in
      scenario.identifier.text
    }
    let covered = coversValues(of: covers)

    for text in covered where !holds(supplied, text) {
      throw .coversWithoutScenario(text)
    }

    for text in supplied where !holds(covered, text) {
      throw .scenarioNotCovered(text)
    }

    return .array(
      sorted.map { scenario in
        scenario.canonical
      },
    )
  }

  /// The route's own members: type, covers, gating and procedure (§89.4).
  func routeValue(of input: RouteFingerprintInput) -> CanonicalValue {
    .members([
      "type": typeValue(of: input.type),
      "covers": .strings(coversValues(of: input.covers)),
      "gates_verification": .boolean(input.gatesVerification),
      "procedure": procedureValue(of: input.procedure),
    ])
  }

  /// Whether `texts` holds `text`, compared by UTF-8 bytes: `==` treats two Unicode forms of a
  /// name as one.
  private func holds(
    _ texts: [String],
    _ text: String,
  ) -> Bool {
    texts.contains { other in
      other.isExactlyEqual(to: text)
    }
  }

  /// Scenario ids as a set: each once, in byte order.
  private func coversValues(of covers: [ScenarioIdentifier]) -> [String] {
    let sorted = covers.map(\.text).sorted { lhs, rhs in
      lhs.precedesExactly(rhs)
    }
    var kept: [String] = []

    for text in sorted {
      if let last = kept.last, last.isExactlyEqual(to: text) {
        continue
      }

      kept.append(text)
    }

    return kept
  }

  private func typeValue(of type: ValidationType) -> CanonicalValue {
    guard case let .custom(name) = type else {
      return .members(["kind": .string(type.kindName)])
    }

    return .members([
      "kind": .string(type.kindName),
      "name": .string(name.text),
    ])
  }

  private func procedureValue(of procedure: Procedure?) -> CanonicalValue {
    guard let procedure else {
      return .null
    }

    return .members([
      "setup": .strings(procedure.setup),
      "steps": .strings(procedure.steps),
      "reset": .strings(procedure.reset),
    ])
  }
}
