import Testing
@testable import UseCasesCLI

/// The compatibility parser (args/parse.ts): exact-token matching, first
/// occurrence for single values, a value-bearing flag swallowing the next token
/// even when it looks like a flag, and nothing read past a `--` separator.
struct ArgumentScannerTests {
  @Test(arguments: [
    (["--repo", "x"], "x"),
    (["--repo", "x", "--repo", "y"], "x"),
    (["--repo", "--json"], "--json"),
    (["--repo", ""], ""),
  ])
  func `reads the token after the first occurrence`(
    arguments: [String],
    expected: String,
  ) {
    #expect(ArgumentScanner.value(after: "--repo", in: arguments) == expected)
  }

  @Test(arguments: [
    [],
    ["--repo"],
    ["--repo=x"],
    ["--REPO", "x"],
    ["-repo", "x"],
  ])
  func `reads nothing without an exact token followed by a value`(arguments: [String]) {
    #expect(ArgumentScanner.value(after: "--repo", in: arguments) == nil)
  }

  @Test(arguments: [
    (["--tag", "a", "--tag", "b"], ["a", "b"] as [String]?),
    (["--tag", "a", "--tag"], ["a"]),
    (["--tag", "", "--tag", "b"], ["b"]),
    (["--tag", ""], nil),
    (["--tag", "--tag", "x"], ["--tag", "x"]),
    ([], nil),
  ])
  func `collects every non-empty value of a repeatable flag`(
    arguments: [String],
    expected: [String]?,
  ) {
    #expect(ArgumentScanner.values(after: "--tag", in: arguments) == expected)
  }

  @Test(arguments: [
    ("12", 12.0 as Double?),
    (" 12 ", 12),
    ("0x10", 16),
    ("1e3", 1000),
    ("-5", -5),
    (".5", 0.5),
    ("5.", 5),
    ("1.5", 1.5),
    ("", nil),
    ("Infinity", nil),
    ("-Infinity", nil),
    ("NaN", nil),
    ("12px", nil),
    ("1_000", nil),
  ])
  func `reads a number the way JavaScript's Number does`(
    text: String,
    expected: Double?,
  ) {
    #expect(ArgumentScanner.number(after: "--n", in: ["--n", text]) == expected)
  }

  @Test
  func `parses each flag by its kind`() {
    let specifications = [
      FlagSpecification(key: "json", name: "--json", kind: .boolean, summary: ""),
      FlagSpecification(key: "repo", name: "--repo", kind: .string, summary: ""),
      FlagSpecification(key: "tag", name: "--tag", kind: .string, summary: "", isRepeatable: true),
      FlagSpecification(key: "limit", name: "--limit", kind: .integer, summary: ""),
      FlagSpecification(key: "absent", name: "--absent", kind: .string, summary: ""),
    ]

    let flags = ArgumentScanner.parseFlags(
      ["--repo", "r", "--tag", "a", "--limit", "3", "--tag", "b", "--json"],
      specifications: specifications,
    )

    #expect(flags["json"] == .boolean(true))
    #expect(flags["repo"] == .string("r"))
    #expect(flags["tag"] == .strings(["a", "b"]))
    #expect(flags["limit"] == .number(3))
    #expect(flags["absent"] == nil)
  }

  @Test
  func `ignores everything after the separator`() {
    let specifications = [
      FlagSpecification(key: "json", name: "--json", kind: .boolean, summary: ""),
      FlagSpecification(key: "out", name: "--out", kind: .string, summary: ""),
    ]

    let flags = ArgumentScanner.parseFlags(
      ["run", "--", "--out", "evil", "--json"],
      specifications: specifications,
    )

    #expect(flags["json"] == .boolean(false))
    #expect(flags["out"] == nil)
  }
}
