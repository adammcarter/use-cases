import Testing
@testable import UseCasesCLI

struct DesignedCommandTests {
  @Test
  func `the commands this build has are the ones the command line reads`() {
    let built = Set(DesignedCommand.allCases.filter(\.isBuilt).map(\.rawValue))

    #expect(built == UseCasesCommand.commandNames)
  }

  @Test
  func `every command of chapter 16 section 2 is designed`() {
    #expect(DesignedCommand.allCases.map(\.rawValue) == [
      "validate", "status", "verify", "record", "links", "search", "show", "save", "remove",
      "apply", "approve", "init", "hooks", "prune", "render", "docs", "mcp",
    ])
  }

  @Test
  func `every command of the design is built`() {
    let unbuilt = DesignedCommand.allCases.filter { !$0.isBuilt }.map(\.rawValue)

    #expect(unbuilt == [])
  }
}
