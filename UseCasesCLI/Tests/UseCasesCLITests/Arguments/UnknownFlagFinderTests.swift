import Testing
@testable import UseCasesCLI

/// Unknown-flag detection (args/validate.ts): the allowlist is every flag any
/// command declares plus the globals, values of value-bearing flags are skipped,
/// and nothing after `--` is inspected.
struct UnknownFlagFinderTests {
  @Test(arguments: [
    (["schema", "list", "--bogus"], ["--bogus"]),
    (["schema", "list", "--bogus", "-x", "--bogus"], ["--bogus", "-x", "--bogus"]),
    (["doctor", "roots", "--repo=."], ["--repo=."]),
    (["doctor", "roots", "--repo", "--bogus"], []),
    (["schema", "list", "--", "--bogus"], []),
    (["schema", "list", "-1"], []),
    (["schema", "list", "-"], []),
    (["schema", "list", "-ab"], []),
    (["schema", "list", "-Z"], ["-Z"]),
    (["schema", "list", "---"], ["---"]),
    (["x", "--tag", "--nope"], []),
    (["x", "--strict", "--nope"], ["--nope"]),
    (["x", "--write", "--flag", "--nope"], []),
    (["x", "--tarball", "--nope"], []),
    (["x", "--installed-root", "--nope"], []),
  ])
  func `reports only the flags nothing declares`(
    arguments: [String],
    expected: [String],
  ) {
    let unknown = UnknownFlagFinder.unknownFlags(
      in: arguments,
      commands: CommandRegistry.allCommands,
    )

    #expect(unknown == expected)
  }

  @Test
  func `accepts every flag every registered command declares`() {
    let everyFlag = CommandRegistry.allCommands.flatMap { command in
      command.flags.filter { $0.kind == .boolean }.map(\.name)
    }

    let unknown = UnknownFlagFinder.unknownFlags(
      in: everyFlag,
      commands: CommandRegistry.allCommands,
    )

    #expect(unknown.isEmpty)
  }
}
