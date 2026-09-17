import Testing
@testable import UseCasesCLI

/// Longest token-path prefix wins; anything unmatched falls through to the
/// builtins.
struct CommandMatcherTests {
  @Test(arguments: [
    (["schema", "list"], "schema.list" as String?),
    (["schema", "list", "extra", "--json"], "schema.list"),
    (["workflow", "mode"], "workflow.get-mode"),
    (["scan"], "markers.scan"),
    (["scan", "list"], "markers.scan"),
    (["approve-run", "--request", "x"], "showcase.approve_run"),
    (["schema"], nil),
    (["--json", "schema", "list"], nil),
    ([], nil),
    (["Schema", "list"], nil),
    (["init"], nil),
    (["version"], nil),
  ])
  func `matches the longest registered path prefix`(
    arguments: [String],
    expected: String?,
  ) {
    let match = CommandMatcher.match(arguments, in: CommandRegistry.allCommands)

    #expect(match?.command == expected)
  }
}
