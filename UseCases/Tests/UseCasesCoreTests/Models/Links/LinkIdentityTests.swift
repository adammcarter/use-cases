import Testing
@testable import UseCasesCore

struct LinkIdentityTests {
  private func identity(
    route: String?,
    binding: String = "code",
  ) throws -> LinkIdentity {
    try LinkIdentity(
      useCase: UseCaseIdentifier(validating: "app.toggle"),
      route: route.map { text in
        try RouteIdentifier(validating: text)
      },
      binding: BindingIdentifier(validating: binding),
    )
  }

  @Test
  func `placement is the role`() throws {
    #expect(try identity(route: nil).role == .implementation)
    #expect(try identity(route: "unit").role == .validation)
  }

  @Test
  func `the key prefix is the marker id`() throws {
    #expect(try identity(route: nil).keyPrefix == "app.toggle#code")
    #expect(try identity(route: "unit").keyPrefix == "app.toggle#unit.code")
  }

  @Test
  func `a message names the binding, its route and its use case`() throws {
    #expect(try identity(route: nil).subject == "binding 'code' of use case 'app.toggle'")
    #expect(
      try identity(route: "unit").subject
        == "binding 'code' of route 'unit' of use case 'app.toggle'",
    )
  }

  @Test
  func `the same binding in different routes is a different identity`() throws {
    #expect(try identity(route: nil) != identity(route: "unit"))
    #expect(try identity(route: "a") != identity(route: "b"))
    #expect(try identity(route: "a") == identity(route: "a"))
  }
}
