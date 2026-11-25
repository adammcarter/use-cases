import Testing
@testable import UseCasesCore

struct ValidationRouteTests {
  private func route(_ members: JSONMembers) throws -> ValidationRoute {
    try ValidationRoute(authored: AuthoredObject(authored(members.json), at: "validation[0]"))
  }

  @Test
  func `a route gates verification when it does not say otherwise`() throws {
    let route = try route(DefinitionSamples.route)

    #expect(route.gatesVerification)
    #expect(ValidationRoute.defaultGatesVerification)
  }

  @Test(arguments: [true, false])
  func `a route that says whether it gates is read as written`(gates: Bool) throws {
    let route = try route(DefinitionSamples.route.setting("gates_verification", "\(gates)"))

    #expect(route.gatesVerification == gates)
  }

  @Test
  func `a route holds its type, covers, procedure, bindings and resources`() throws {
    let members = DefinitionSamples.route
      .setting("covers", #"["b","a"]"#)
      .setting("procedure", #"{"steps":["Sign in."]}"#)
      .setting("bindings", #"[{"id":"t","kind":"manual","locator":{"file":"tests/t.py"}}]"#)
      .setting(
        "resources",
        #"[{"kind":"file","path":"fixtures/u.json"},{"kind":"glob","pattern":"s/**"}]"#,
      )

    let route = try route(members)

    #expect(route.identifier.text == "unit-tests")
    #expect(route.type == .unit)
    #expect(route.covers.map(\.text) == ["b", "a"])
    #expect(route.procedure?.steps == ["Sign in."])
    #expect(route.bindings.map(\.identifier.text) == ["t"])
    #expect(route.resources.count == 2)
  }

  @Test
  func `a route with no procedure, bindings or resources has none`() throws {
    let route = try route(DefinitionSamples.route)

    #expect(route.procedure == nil)
    #expect(route.bindings.isEmpty)
    #expect(route.resources.isEmpty)
  }

  @Test
  func `a gates_verification that is not true or false is refused`() {
    #expect(throws: AuthoredShapeError.self) {
      try route(DefinitionSamples.route.setting("gates_verification", #""no""#))
    }
  }

  @Test
  func `a cover that is off the id grammar names its place`() {
    #expect(
      throws: AuthoredShapeError.invalidIdentifier(
        location: "validation[0].covers[0]",
        .invalidCharacter("B", within: "Bad"),
      ),
    ) {
      try route(DefinitionSamples.route.setting("covers", #"["Bad"]"#))
    }
  }
}
