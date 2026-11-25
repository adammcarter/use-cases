import Testing
@testable import UseCasesCore

struct ScopeConfigurationLoaderTests {
  private func loader() throws -> ScopeConfigurationLoader {
    try ScopeConfigurationLoader(
      yamlReader: StrictYAMLReader(),
      schema: BundledSchemaLoader().loadChecker(for: .workspace),
      configurationReader: ScopeConfigurationReader(),
    )
  }

  private func problems(
    _ text: String,
    at path: String = "use-cases.yml",
  ) throws -> [ScopeSettingsProblem] {
    do {
      _ = try loader().load(
        fromText: text,
        at: workspacePath(path),
      )
    } catch let error as ScopeSettingsError {
      return error.problems
    }

    return []
  }

  @Test
  func `a root file is read with its prefix and defaults`() throws {
    let configuration = try loader().load(
      fromText: "schema_version: 1\nroot: true\nprefix: shop\n",
      at: workspacePath("use-cases.yml"),
    )

    #expect(configuration.declaresRoot)
    #expect(configuration.prefix?.text == "shop")
    #expect(configuration.useCasesDirectory.text == "use-cases")
    #expect(configuration.rootSettings != nil)
  }

  @Test
  func `a child file has no root settings`() throws {
    let configuration = try loader().load(
      fromText: "schema_version: 1\nprefix: pay\n",
      at: workspacePath("services/pay/use-cases.yml"),
    )

    #expect(!configuration.declaresRoot)
    #expect(configuration.rootSettings == nil)
  }

  @Test
  func `a note at the end of a settings line is kept`() throws {
    let configuration = try loader().load(
      fromText: "schema_version: 1\nprefix: pay   # the namespace\n",
      at: workspacePath("pay/use-cases.yml"),
    )

    #expect(configuration.prefix?.text == "pay")
  }

  @Test
  func `YAML that is refused is a problem at its line, without the file repeated`() throws {
    let found = try problems("schema_version: 1\nschema_version: 2\n")
    let problem = try #require(found.first)

    #expect(found.count == 1)
    #expect(problem.position?.line == 2 || problem.position?.line == 1)
    #expect(problem.message == "duplicate key 'schema_version'")
    #expect(problem.code == "duplicate-key")
  }

  @Test
  func `a schema failure is a problem that says where the value is`() throws {
    let found = try problems("schema_version: 2\n")

    #expect(found.count == 1)
    #expect(found.first?.code == "schema-const")
    #expect(found.first?.message.hasSuffix("at schema_version") == true)
  }

  @Test
  func `a missing schema version is a problem`() throws {
    #expect(try problems("prefix: pay\n").count == 1)
  }

  @Test
  func `the configuration reader's problems are all reported`() throws {
    let found = try problems(
      "schema_version: 1\nsign_off: required\nfreshness: {}\n",
      at: "svc/use-cases.yml",
    )

    #expect(found.count == 2)
    #expect(found.allSatisfy { problem in problem.code == "root-only-setting" })
  }

  @Test
  func `a nested workspace's own root-only settings are its own business`() throws {
    let configuration = try loader().load(
      fromText: "schema_version: 1\nroot: true\nsign_off: required\n",
      at: workspacePath("vendor/auth/use-cases.yml"),
    )

    #expect(configuration.declaresRoot)
    #expect(configuration.rootSettings?.signOff != nil)
  }
}
