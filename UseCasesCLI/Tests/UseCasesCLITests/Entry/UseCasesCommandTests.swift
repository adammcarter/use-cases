import Testing
@testable import UseCasesCLI

/// swift-argument-parser is the entry point, and it must hand every raw
/// argument through untouched: the TypeScript parser's semantics (help and
/// version anywhere, `--` as a payload separator, no `--flag=value` form) are
/// reproduced after it, so anything the library consumed or rewrote would be
/// an observable change.
struct UseCasesCommandTests {
  @Test(arguments: [
    [],
    ["--help"],
    ["-h"],
    ["help"],
    ["--version"],
    ["-v"],
    ["version", "--json"],
    ["--"],
    ["--", "--help"],
    ["evidence", "record", "--run", "--", "pytest", "-q", "--tb=short"],
    ["a", "--", "b", "--", "c"],
    ["-abc"],
    ["-"],
    [""],
    ["--repo=."],
    ["-1"],
    ["--generate-completion-script"],
    ["--generate-completion-script", "zsh"],
    ["--experimental-dump-help"],
    ["--experimental-discussion"],
    ["frobnicate", "--json", "--json"],
    ["matrix", "list", "--tag", "a", "--tag", "b"],
  ])
  func `passes every raw argument through unchanged`(raw: [String]) throws {
    let forwarded = try UseCasesCommand.forwardedArguments(raw)

    #expect(forwarded == raw)
  }
}
