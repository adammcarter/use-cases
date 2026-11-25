import Testing
@testable import UseCasesCLI

struct CommandWordsTests {
  @Test(arguments: [
    (["validate"], "validate"),
    (["--json", "validate"], "validate"),
    (["--workspace", "/w", "--json", "status", "shop"], "status"),
    (["--quiet", "--workspace", "status", "links"], "links"),
    (["--workspace=/w", "nosuch"], "nosuch"),
    (["--help", "help", "status"], "help"),
  ])
  func `the command is the first word that is no option and no option's value`(
    arguments: [String],
    command: String,
  ) {
    #expect(CommandWords(arguments).command == command)
  }

  @Test(arguments: [
    [],
    ["--json"],
    ["--workspace", "validate"],
    ["--workspace", "/w", "--help"],
    ["--", "validate"],
    ["-h"],
  ])
  func `no word names a command when only options and their values are there`(
    arguments: [String],
  ) {
    #expect(CommandWords(arguments).command == nil)
  }

  @Test
  func `help and json are found wherever they stand before a double dash`() {
    #expect(CommandWords(["--help"]).asksForHelp)
    #expect(CommandWords(["-h", "--json"]).asksForHelp)
    #expect(CommandWords(["--json", "nosuch"]).asksForJSON)
    #expect(!CommandWords(["nosuch"]).asksForJSON)
    #expect(!CommandWords(["--", "--help"]).asksForHelp)
    #expect(!CommandWords(["--", "--json"]).asksForJSON)
  }
}
