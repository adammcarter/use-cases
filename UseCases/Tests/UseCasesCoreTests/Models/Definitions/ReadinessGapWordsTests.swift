import Testing
@testable import UseCasesCore

struct ReadinessGapWordsTests {
  @Test
  func `a gap a test pins is told in the words the test pins`() throws {
    #expect(ReadinessGap.valueTier.words == "value_tier")
    #expect(ReadinessGap.intent.words == "intent")
    #expect(
      try ReadinessGap.uncoveredScenario(ScenarioIdentifier(validating: "adds")).words
        == "a gating route covering scenario adds",
    )
  }

  @Test
  func `the two gaps no test pins are told in plain words`() {
    #expect(ReadinessGap.scenarios.words == "a scenario")
    #expect(ReadinessGap.validation.words == "a validation route")
  }
}
