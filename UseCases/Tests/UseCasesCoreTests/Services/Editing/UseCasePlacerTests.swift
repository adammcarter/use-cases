import Testing
@testable import UseCasesCore

struct UseCasePlacerTests {
  private let placer = UseCasePlacer()
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("use-cases/dark.yml", YAMLSamples.file(prefix: "dark", YAMLSamples.useCase()))
    try fixture.write(
      "use-cases/more/dark-too.yml",
      YAMLSamples.file(prefix: "dark", YAMLSamples.useCase("other")),
    )
    try fixture.write("use-cases/flat.yml", YAMLSamples.file(YAMLSamples.useCase("loose")))
    try fixture.write("packages/auth/use-cases.yml", YAMLSamples.child(prefix: "auth"))
    try fixture.write("packages/plain/use-cases.yml", "schema_version: 1\n")
  }

  private func placement(_ identifier: String) throws -> UseCasePlacement {
    try placer.place(
      UseCaseIdentifier(validating: identifier),
      in: fixture.loaded(),
    )
  }

  private func path(_ text: String) throws -> WorkspacePath {
    try WorkspacePath(validating: text)
  }

  @Test
  func `a use case joins the file that holds its group, the first by path when several do`(
  ) throws {
    #expect(try placement("app.dark.contrast") == .existing(file: path("use-cases/dark.yml")))
  }

  @Test
  func `a new group gets a file named for it, with the group as its prefix`() throws {
    #expect(
      try placement("app.refunds.partial")
        == .new(
          file: path("use-cases/refunds.yml"),
          prefix: Namespace(validating: "refunds"),
        ),
    )
  }

  @Test
  func `each segment of a group below the first is a folder, the last is the file`() throws {
    #expect(
      try placement("app.payments.card.refund")
        == .new(
          file: path("use-cases/payments/card.yml"),
          prefix: Namespace(validating: "payments.card"),
        ),
    )
  }

  @Test
  func `a group under a child scope's namespace goes into that scope's use cases folder`() throws {
    #expect(
      try placement("app.auth.login.ok")
        == .new(
          file: path("packages/auth/use-cases/login.yml"),
          prefix: Namespace(validating: "login"),
        ),
    )
  }

  @Test
  func `a scope without a prefix shares its parent's namespace and the parent wins`() throws {
    #expect(try placement("app.orders.list") == .new(
      file: path("use-cases/orders.yml"),
      prefix: Namespace(validating: "orders"),
    ))
  }

  @Test
  func `an id with one segment has no group`() {
    #expect(throws: UseCaseEditingError.noGroup(identifier: "orphan")) {
      try placement("orphan")
    }
  }

  @Test(arguments: ["app.loose", "app.auth.straight"])
  func `an id straight under a scope's namespace needs a group`(identifier: String) {
    let namespace = identifier.hasPrefix("app.auth") ? "app.auth" : "app"

    #expect(
      throws: UseCaseEditingError.needsGroup(
        identifier: identifier,
        namespace: namespace,
      ),
    ) {
      try placement(identifier)
    }
  }

  @Test
  func `an id under no scope's namespace is refused, naming the workspace's`() {
    #expect(
      throws: UseCaseEditingError.outsideNamespaces(
        identifier: "other.group.thing",
        namespace: "app",
      ),
    ) {
      try placement("other.group.thing")
    }
  }
}
