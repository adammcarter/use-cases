import Testing
@testable import UseCasesCore

/// A glob matches only files the code scan reads (chapter 11 §42): the set the acceptance suite
/// pins in `test_a_resource_glob_matches_only_files_the_scan_reads`.
struct RouteFingerprintComputerGlobTests {
  @Test(
    arguments: [
      "vendor/*.json",
      ".git/*",
      ".use-cases/**",
      "use-cases.yml",
      "use-cases-bridge.yml",
      "use-case-groups.yml",
      "use-cases/*.yml",
      "nested/*.json",
    ],
  )
  func `a glob over files the scan never reads matches nothing`(pattern: String) throws {
    let fixture = try FreshnessFixture(
      root: FreshnessSamples.root(exclude: ["vendor"]),
      definitions: FreshnessSamples.definitions(resources: [FreshnessSamples.glob(pattern)]),
    )
    try fixture.write("vendor/a.json", "{}")
    try fixture.write(".git/HEAD", "ref: x\n")
    try fixture.write(".use-cases/store.json", "{}")
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n")
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")
    try fixture.write("nested/use-cases.yml", "schema_version: 1\nroot: true\n")
    try fixture.write("nested/a.json", "{}")

    let result = try fixture.fingerprints()

    #expect(result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(result.problems.count == 1)
    #expect(result.problems.first?.contains("matches nothing") == true)
  }

  @Test
  func `a glob that matches a file the scan reads is valid`() throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(resources: [FreshnessSamples.glob("**/*.json")]),
    )
    try fixture.write("fixtures/a.json", "{}")

    #expect(try !fixture.fingerprints().isInvalid)
  }

  @Test(
    arguments: [
      ("fixtures/**/*.json", true),
      ("fixtures/*.json", true),
      ("*a.json", false),
      ("Fixtures/*.json", false),
      ("fixtures/?.json", true),
    ],
  )
  func `globs use the one dialect`(
    pattern: String,
    matches: Bool,
  ) throws {
    let fixture = try FreshnessFixture(
      definitions: FreshnessSamples.definitions(resources: [FreshnessSamples.glob(pattern)]),
    )
    try fixture.write("fixtures/a.json", "{}")

    #expect(try fixture.fingerprints().isInvalid == !matches)
  }
}
