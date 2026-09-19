import Testing
@testable import UseCasesCore

/// The canonical agent list.
struct CanonicalAgentTests {
  @Test
  func `the canonical agents are the TypeScript's, in its order`() throws {
    #expect(try CanonicalAgent.allCases.map(\.rawValue) == SkillsFixtures
      .strings("canonical_agents"))
  }
}
