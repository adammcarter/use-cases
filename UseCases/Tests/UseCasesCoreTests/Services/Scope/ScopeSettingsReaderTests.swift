import Testing
@testable import UseCasesCore

struct ScopeSettingsReaderTests {
  private func reader() throws -> ScopeSettingsReader {
    try ScopeSettingsReader(
      configurationLoader: ScopeConfigurationLoader(
        yamlReader: StrictYAMLReader(),
        schema: BundledSchemaLoader().loadChecker(for: .workspace),
        configurationReader: ScopeConfigurationReader(),
      ),
    )
  }

  @Test
  func `the root's settings carry its folder and exclusions`() throws {
    let settings = try reader().readSettings(
      fromText: """
      schema_version: 1
      root: true
      use_cases_dir: specs
      discovery:
        exclude: [build/**, vendor]
      """,
      at: workspacePath("use-cases.yml"),
    )

    #expect(settings.isRoot)
    #expect(settings.useCasesDirectory.text == "specs")
    #expect(settings.excludes.map(\.text) == ["build/**", "vendor"])
  }

  @Test
  func `a child's settings have the default folder and no exclusions`() throws {
    let settings = try reader().readSettings(
      fromText: "schema_version: 1\n",
      at: workspacePath("svc/use-cases.yml"),
    )

    #expect(!settings.isRoot)
    #expect(settings.useCasesDirectory.text == "use-cases")
    #expect(settings.excludes.isEmpty)
  }

  @Test
  func `a file that is not valid settings throws its problems`() throws {
    #expect(throws: ScopeSettingsError.self) {
      try reader().readSettings(
        fromText: "prefix: x\n",
        at: workspacePath("use-cases.yml"),
      )
    }
  }
}
