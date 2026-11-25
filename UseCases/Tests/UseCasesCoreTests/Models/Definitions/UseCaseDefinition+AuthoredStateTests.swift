import Testing
@testable import UseCasesCore

struct UseCaseDefinitionAuthoredStateTests {
  private func state(of members: JSONMembers) throws -> AuthoredState {
    try UseCaseDefinition(authored: AuthoredObject(authored(members.json), at: "")).authoredState
  }

  private func identifier(_ text: String) throws -> ScenarioIdentifier {
    try ScenarioIdentifier(validating: text)
  }

  @Test
  func `a use case with all of it written is READY`() throws {
    #expect(try state(of: DefinitionSamples.useCase) == .ready)
  }

  @Test
  func `an id and a title alone is a DRAFT missing everything else`() throws {
    #expect(
      try state(of: DefinitionSamples.draft)
        == .draft(missing: [.valueTier, .intent, .scenarios, .validation]),
    )
  }

  @Test
  func `without a value tier it is a DRAFT`() throws {
    #expect(
      try state(of: DefinitionSamples.useCase.removing("value_tier"))
        == .draft(missing: [.valueTier]),
    )
  }

  @Test
  func `without an intent it is a DRAFT`() throws {
    #expect(
      try state(of: DefinitionSamples.useCase.removing("intent")) == .draft(missing: [.intent]),
    )
  }

  @Test
  func `the pinned order is value tier, then intent`() throws {
    let members = DefinitionSamples.useCase.removing("intent").removing("value_tier")

    #expect(try state(of: members) == .draft(missing: [.valueTier, .intent]))
  }

  @Test
  func `a scenario that only a non-gating route covers keeps a use case DRAFT`() throws {
    let members = DefinitionSamples.useCase.setting(
      "validation",
      "[\(DefinitionSamples.route.setting("gates_verification", "false").json)]",
    )

    #expect(
      try state(of: members)
        == .draft(missing: [.uncoveredScenario(identifier("valid-credentials"))]),
    )
  }

  @Test
  func `each scenario no gating route covers is missing, in scenario order`() throws {
    let members = DefinitionSamples.useCase
      .setting(
        "scenarios",
        "[\(DefinitionSamples.scenario(id: "b").json),\(DefinitionSamples.scenario(id: "a").json),"
          + "\(DefinitionSamples.scenario(id: "c").json)]",
      )
      .setting(
        "validation",
        "[\(DefinitionSamples.route(id: "unit-tests", covers: ["c"]).json)]",
      )

    #expect(
      try state(of: members)
        == .draft(
          missing: [
            .uncoveredScenario(identifier("b")),
            .uncoveredScenario(identifier("a")),
          ],
        ),
    )
  }

  @Test
  func `one gating route among several is enough to cover a scenario`() throws {
    let gating = DefinitionSamples.route(id: "gate", covers: ["valid-credentials"])
    let manual = DefinitionSamples.route(id: "manual", covers: ["valid-credentials"])
      .setting("gates_verification", "false")
    let members = DefinitionSamples.useCase.setting("validation", "[\(manual.json),\(gating.json)]")

    #expect(try state(of: members) == .ready)
  }

  @Test
  func `scenarios with no route at all are missing a validation and their coverage`() throws {
    let members = DefinitionSamples.useCase.removing("validation")

    #expect(
      try state(of: members)
        == .draft(
          missing: [
            .validation,
            .uncoveredScenario(identifier("valid-credentials")),
          ],
        ),
    )
  }
}
