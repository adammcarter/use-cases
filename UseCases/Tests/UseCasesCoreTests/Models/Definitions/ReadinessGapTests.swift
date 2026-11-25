import Testing
@testable import UseCasesCore

struct ReadinessGapTests {
  @Test
  func `the gaps the acceptance tests pin read as they do there`() throws {
    #expect(ReadinessGap.valueTier.pinnedText == "value_tier")
    #expect(ReadinessGap.intent.pinnedText == "intent")
    #expect(
      try ReadinessGap.uncoveredScenario(ScenarioIdentifier(validating: "adds")).pinnedText
        == "a gating route covering scenario adds",
    )
  }

  @Test(arguments: [ReadinessGap.scenarios, ReadinessGap.validation])
  func `a gap no chapter or test words has no pinned text`(gap: ReadinessGap) {
    #expect(gap.pinnedText == nil)
  }
}
