import Testing
@testable import UseCasesCore

struct ScopeSettingsLoaderTests {
  private let reader = ScopeSettingsLoader(
    fileSystem: LocalFileSystem(),
    settingsReader: MockScopeSettingsReader(),
  )

  @Test
  func `a configuration file reads as the settings its text says`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "root: true\nuse_cases_dir: specs\nexclude: build/**\n")

    let settings = try reader.loadSettings(
      at: directory.location(of: "use-cases.yml"),
      path: .at("use-cases.yml"),
    )

    #expect(settings.isRoot)
    #expect(settings.useCasesDirectory.text == "specs")
    #expect(settings.excludes.map(\.text) == ["build/**"])
  }

  @Test
  func `a file that is not there cannot be read`() throws {
    let directory = try TemporaryDirectory()

    #expect(throws: ScopeSettingsLoadingError.self) {
      try reader.loadSettings(
        at: directory.location(of: "use-cases.yml"),
        path: .at("use-cases.yml"),
      )
    }
  }

  @Test
  func `text that is not valid UTF-8 is unreadable`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", bytes: [0xFF, 0xFE])
    let file = directory.location(of: "use-cases.yml")

    #expect(throws: ScopeSettingsLoadingError.unreadable(.notUTF8(file))) {
      try reader.loadSettings(
        at: file,
        path: .at("use-cases.yml"),
      )
    }
  }

  @Test
  func `settings the reader refuses come back with every problem`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "invalid\n")
    let path = try WorkspacePath.at("use-cases.yml")

    do throws(ScopeSettingsLoadingError) {
      _ = try reader.loadSettings(
        at: directory.location(of: "use-cases.yml"),
        path: path,
      )
      Issue.record("the settings were accepted")
    } catch {
      guard case let .invalid(settingsError) = error else {
        Issue.record("expected invalid settings, got \(error)")
        return
      }

      #expect(settingsError.problems.map(\.code.text) == ["mock-invalid"])
      #expect(error.summary == "the settings are invalid")
    }
  }
}
