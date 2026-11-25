import Foundation
import Testing
@testable import UseCasesCore

struct DefinitionFileLoaderTests {
  private func loader() throws -> DefinitionFileLoader {
    try DefinitionFileLoader(
      fileSystem: LocalFileSystem(),
      yamlReader: StrictYAMLReader(),
      technicalFieldChecker: TechnicalFieldChecker(),
      markerBindingChecker: MarkerBindingChecker(),
      schema: BundledSchemaLoader().loadChecker(for: .useCases),
      fileReader: DefinitionFileReader(),
    )
  }

  private func load(
    _ text: String,
  ) throws -> Result<DefinitionFile, DefinitionFileLoadingError> {
    let directory = try TemporaryDirectory()
    try directory.write("a.yml", text)

    do {
      return try .success(
        loader().load(
          at: directory.location(of: "a.yml"),
          path: workspacePath("a.yml"),
        ),
      )
    } catch let error as DefinitionFileLoadingError {
      return .failure(error)
    }
  }

  private func problems(_ text: String) throws -> [Diagnostic] {
    guard case let .failure(.invalid(diagnostics)) = try load(text) else {
      return []
    }

    return diagnostics
  }

  @Test
  func `a valid file gives its prefix and use cases in the order written`() throws {
    let result = try load(YAMLSamples.file(
      prefix: "p",
      YAMLSamples.useCase("b"),
      YAMLSamples.useCase("a"),
    ))
    let file = try result.get()

    #expect(file.prefix?.text == "p")
    #expect(file.useCases.map(\.localIdentifier.text) == ["b", "a"])
  }

  @Test
  func `a file that is missing is a problem naming it`() throws {
    let directory = try TemporaryDirectory()
    let loader = try loader()
    let path = try workspacePath("gone.yml")

    do {
      _ = try loader.load(
        at: directory.location(of: "gone.yml"),
        path: path,
      )
      Issue.record("a missing file was read")
    } catch {
      switch error {
      case let .invalid(diagnostics):
        #expect(diagnostics.map(\.code.text) == ["unreadable-definition"])
        #expect(diagnostics.first?.file.text == "gone.yml")
      }
    }
  }

  @Test
  func `YAML that is refused is a problem at its line`() throws {
    let found = try problems("use_cases:\n  - id: a\n    id: b\n")

    #expect(found.count == 1)
    #expect(found.first?.code == "duplicate-key")
    #expect(found.first?.position != nil)
  }

  @Test
  func `a technical field is reported once, without the schema's own complaint about it`() throws {
    let found = try problems(YAMLSamples.file(YAMLSamples.useCase(extra: "    runner: swift\n")))

    #expect(found.map(\.code.text) == ["technical-field"])
  }

  @Test
  func `a technical field does not hide the other problems in the file`() throws {
    let found = try problems(
      YAMLSamples.file(
        YAMLSamples.useCase(
          title: "42",
          extra: "    command: run\n",
        ),
      ),
    )

    #expect(Set(found.map(\.code.text)) == ["schema-type", "technical-field"])
    #expect(found.contains { problem in problem.message.contains("42 is not of type 'string'") })
    #expect(found.contains { problem in problem.message.contains("`command`") })
  }

  @Test
  func `an unknown field beside a technical one is still reported`() throws {
    let found = try problems(
      YAMLSamples.file(YAMLSamples.useCase(extra: "    runner: swift\n    stray: true\n")),
    )

    #expect(Set(found.map(\.code.text)) == ["schema-additionalProperties", "technical-field"])
    #expect(found.contains { problem in problem.message.contains("'stray'") })
  }

  @Test
  func `with a technical field and a schema failure the file is still not read as definitions`()
    throws
  {
    let found = try problems(
      YAMLSamples.file(
        YAMLSamples.useCase(
          title: "42",
          extra: "    runner: swift\n",
        ),
      ).replacing(
        "covers: [on-state]",
        with: "covers: [nowhere]",
      ),
    )

    #expect(!found.contains { problem in problem.code == "unknown-scenario" })
  }

  @Test
  func `a schema failure is a problem with the keyword in its code`() throws {
    let found = try problems(YAMLSamples.file(YAMLSamples.useCase(title: "42")))

    #expect(found.map(\.code.text) == ["schema-type"])
    #expect(found.first?.message.contains("42 is not of type 'string'") == true)
  }

  @Test
  func `the reader is asked only after the schema is satisfied`() throws {
    let found = try problems(
      YAMLSamples.file(YAMLSamples.useCase()).replacing(
        "covers: [on-state]",
        with: "covers: [on-state, nowhere]",
      ),
    )

    #expect(found.map(\.code.text) == ["unknown-scenario"])
  }

  @Test
  func `a marker binding is reported once, without the schema's complaints about it`() throws {
    let found = try problems(
      YAMLSamples.file(
        YAMLSamples.useCase(extra: "    bindings:\n      - id: x\n        kind: marker\n"),
      ),
    )

    #expect(found.map(\.code.text) == ["marker-binding-in-yaml"])
    #expect(found.first?.message.contains("need no entry") == true)
    #expect(found.first?.message.contains("binding 'x' of use case 'toggle'") == true)
  }

  @Test
  func `a marker binding on a route is reported once, naming the route`() throws {
    let found = try problems(
      YAMLSamples.file(
        YAMLSamples.useCase(
          extra: "        bindings:\n          - id: t\n            kind: marker\n",
        ),
      ),
    )

    #expect(found.map(\.code.text) == ["marker-binding-in-yaml"])
    #expect(found.first?.message.contains("binding 't' of route 'manual'") == true)
  }

  @Test
  func `a marker binding does not hide the other problems in the file`() throws {
    let found = try problems(
      YAMLSamples.file(
        YAMLSamples.useCase(
          title: "42",
          extra: "    bindings:\n      - id: x\n        kind: marker\n",
        ),
      ),
    )

    #expect(Set(found.map(\.code.text)) == ["marker-binding-in-yaml", "schema-type"])
  }
}
