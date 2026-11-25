import Testing
@testable import UseCasesCore

struct UseCaseDefinitionTests {
  private func definition(_ members: JSONMembers) throws -> UseCaseDefinition {
    try UseCaseDefinition(authored: AuthoredObject(authored(members.json), at: ""))
  }

  @Test
  func `the canonical example of chapter 02 is read whole`() throws {
    let members = DefinitionSamples.useCase
      .setting("description", #""Handles authentication.""#)
      .setting("out_of_scope", #"["Social login.","Password reset."]"#)
      .setting(
        "bindings",
        #"[{"id":"legacy-login","kind":"manual","locator":{"file":"src/login.py"}}]"#,
      )
      .setting(
        "approved",
        JSONMembers([
          "by": jsonString("Sam"),
          "on": jsonString("2026-10-11"),
          "behaviour": jsonString(String(repeating: "0", count: 64)),
        ]).json,
      )

    let useCase = try definition(members)

    #expect(useCase.localIdentifier.text == "authenticate")
    #expect(useCase.title == "Authenticate user")
    #expect(useCase.description == "Handles authentication.")
    #expect(useCase.valueTier == .core)
    #expect(useCase.intent == "Let a valid user in.")
    #expect(useCase.outOfScope == ["Social login.", "Password reset."])
    #expect(useCase.scenarios.map(\.identifier.text) == ["valid-credentials"])
    #expect(useCase.routes.map(\.identifier.text) == ["unit-tests"])
    #expect(useCase.bindings.map(\.identifier.text) == ["legacy-login"])
    #expect(useCase.approval?.approver == "Sam")
  }

  @Test
  func `the least a use case needs is an id and a title`() throws {
    let useCase = try definition(DefinitionSamples.draft)

    #expect(useCase.localIdentifier.text == "success")
    #expect(useCase.title == "Successful login")
    #expect(useCase.description == nil)
    #expect(useCase.valueTier == nil)
    #expect(useCase.intent == nil)
    #expect(useCase.outOfScope.isEmpty)
    #expect(useCase.scenarios.isEmpty)
    #expect(useCase.routes.isEmpty)
    #expect(useCase.bindings.isEmpty)
    #expect(useCase.approval == nil)
  }

  @Test
  func `scenarios and routes keep the order they were written in`() throws {
    let members = DefinitionSamples.useCase
      .setting(
        "scenarios",
        "[\(DefinitionSamples.scenario(id: "zeta").json),"
          + "\(DefinitionSamples.scenario(id: "alpha").json)]",
      )
      .setting(
        "validation",
        "[\(DefinitionSamples.route(id: "b-route", covers: ["zeta"]).json),"
          + "\(DefinitionSamples.route(id: "a-route", covers: ["alpha"]).json)]",
      )

    let useCase = try definition(members)

    #expect(useCase.scenarios.map(\.identifier.text) == ["zeta", "alpha"])
    #expect(useCase.routes.map(\.identifier.text) == ["b-route", "a-route"])
  }

  @Test
  func `a duplicate id is kept as written for the checks to find`() throws {
    let members = DefinitionSamples.useCase.setting(
      "scenarios",
      "[\(DefinitionSamples.scenario.json),\(DefinitionSamples.scenario.json)]",
    )

    #expect(try definition(members).scenarios.count == 2)
  }

  @Test(arguments: ["critical", "core", "supporting"])
  func `each value tier is read`(text: String) throws {
    let useCase = try definition(DefinitionSamples.draft.setting("value_tier", "\"\(text)\""))

    #expect(useCase.valueTier?.rawValue == text)
  }

  @Test
  func `a use case with an id off the grammar is refused`() {
    #expect(
      throws: AuthoredShapeError.invalidIdentifier(
        location: "id",
        .invalidCharacter("B", within: "Bad_Id"),
      ),
    ) {
      try definition(DefinitionSamples.draft.setting("id", #""Bad_Id""#))
    }
  }

  @Test(
    arguments: [
      ("value_tier", "\"vital\""),
      ("title", "4"),
      ("scenarios", "{}"),
      ("validation", #"[{"id":"x"}]"#),
      ("approved", #"{"by":"Sam"}"#),
      ("out_of_scope", #"["ok",2]"#),
    ],
  )
  func `a field of the wrong shape is refused`(
    case example: (key: String, json: String),
  ) {
    #expect(throws: AuthoredShapeError.self) {
      try definition(DefinitionSamples.draft.setting(example.key, example.json))
    }
  }

  @Test
  func `a sample the schema accepts is read`() throws {
    let value = try checked(
      DefinitionSamples.file(DefinitionSamples.useCase),
      against: .useCases,
    )
    let root = try AuthoredObject(value, at: "")
    let item = try #require(root.objects("use_cases").first)

    #expect(try UseCaseDefinition(authored: item).title == "Authenticate user")
  }
}
