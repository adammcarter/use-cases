import Testing
@testable import UseCasesCLI

struct UseCasesCommandTests {
  @Test(arguments: [
    (["--version"], true, false),
    (["--version", "--json"], true, true),
    (["--json", "--version"], true, true),
    ([], false, false),
  ])
  func `reads the version and json flags in any order`(
    arguments: [String],
    isVersion: Bool,
    isJSON: Bool,
  ) throws {
    let command = try UseCasesCommand.parse(arguments)

    #expect(command.version == isVersion)
    #expect(command.json == isJSON)
  }

  @Test
  func `refuses a flag it does not know`() {
    #expect(throws: (any Error).self) {
      try UseCasesCommand.parse(["--nope"])
    }
  }

  @Test(arguments: [
    ["validate"],
    ["--json", "validate"],
    ["validate", "--json"],
    ["--workspace", "/w", "--json", "validate"],
  ])
  func `reads validate with the global options before it or after it`(
    arguments: [String],
  ) throws {
    let command = try UseCasesCommand.parseAsRoot(arguments)

    let validate = try #require(command as? ValidateCommand)
    #expect(validate.global.json == arguments.contains("--json"))
    #expect(validate.global.workspace == (arguments.contains("--workspace") ? "/w" : nil))
  }

  @Test
  func `the workspace named before the command reaches the command`() throws {
    let command = try UseCasesCommand.parseAsRoot(["--workspace", "/w", "validate"])

    let validate = try #require(command as? ValidateCommand)
    #expect(validate.global.workspace == "/w")
  }

  @Test
  func `refuses a command it does not know`() {
    #expect(throws: (any Error).self) {
      try UseCasesCommand.parseAsRoot(["nosuch"])
    }
  }
}
