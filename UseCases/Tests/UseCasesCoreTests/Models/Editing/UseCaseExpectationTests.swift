import Testing
@testable import UseCasesCore

struct UseCaseExpectationTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("use-cases/dark.yml", YAMLSamples.file(prefix: "dark", YAMLSamples.useCase()))
  }

  private func present(
    file: String = "use-cases/dark.yml",
    title: String? = nil,
  ) throws -> UseCaseExpectation {
    let useCase = try #require(fixture.loaded().useCases.first)
    let definition = UseCaseDefinition(
      localIdentifier: useCase.definition.localIdentifier,
      title: title ?? useCase.definition.title,
      description: nil,
      valueTier: useCase.definition.valueTier,
      intent: useCase.definition.intent,
      outOfScope: [],
      scenarios: useCase.definition.scenarios,
      routes: useCase.definition.routes,
      bindings: [],
      approval: nil,
    )

    return try .present(
      identifier: useCase.identifier,
      file: WorkspacePath(validating: file),
      definition: definition,
    )
  }

  @Test
  func `a use case that is there as meant is no divergence`() throws {
    #expect(try present().divergence(in: fixture.loaded()) == nil)
  }

  @Test
  func `a use case in another file, or not as sent, or missing, is told apart`() throws {
    let workspace = try fixture.loaded()

    #expect(try present(file: "use-cases/elsewhere.yml").divergence(in: workspace)?
      .contains("would be in") == true)
    #expect(try present(title: "Other").divergence(in: workspace)?
      .contains("would not read back") == true)

    let missing = try UseCaseExpectation.present(
      identifier: UseCaseIdentifier(validating: "app.dark.gone"),
      file: WorkspacePath(validating: "use-cases/dark.yml"),
      definition: #require(workspace.useCases.first).definition,
    )

    #expect(missing.divergence(in: workspace)?.contains("is not in the workspace") == true)
  }

  @Test
  func `a use case that should be gone is a divergence while it is there`() throws {
    let workspace = try fixture.loaded()

    #expect(
      try UseCaseExpectation.absent(identifier: UseCaseIdentifier(validating: "app.dark.toggle"))
        .divergence(in: workspace)?.contains("would still be") == true,
    )
    #expect(
      try UseCaseExpectation.absent(identifier: UseCaseIdentifier(validating: "app.dark.gone"))
        .divergence(in: workspace) == nil,
    )
  }
}
