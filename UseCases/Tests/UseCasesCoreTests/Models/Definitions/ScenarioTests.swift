import Testing
@testable import UseCasesCore

struct ScenarioTests {
  private func scenario(_ json: String) throws -> Scenario {
    try Scenario(authored: AuthoredObject(authored(json), at: "scenarios[0]"))
  }

  @Test
  func `a scenario keeps its steps in the order written`() throws {
    let scenario = try scenario(DefinitionSamples.scenario.json)

    #expect(scenario.identifier.text == "valid-credentials")
    #expect(scenario.given == ["The user is signed out."])
    #expect(scenario.when == ["The user submits valid credentials."])
    #expect(scenario.then == ["A session is created.", "The dashboard is shown."])
  }

  @Test
  func `given may be left out`() throws {
    let scenario = try scenario(DefinitionSamples.scenario.removing("given").json)

    #expect(scenario.given.isEmpty)
  }

  @Test
  func `a scenario id off the grammar is refused with its place`() {
    #expect(throws: AuthoredShapeError.self) {
      try scenario(DefinitionSamples.scenario.setting("id", #""Valid_Credentials""#).json)
    }
  }
}
