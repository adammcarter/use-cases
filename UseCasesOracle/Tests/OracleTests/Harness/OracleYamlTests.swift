import Testing

/// The reader `ReleaseWorkflowTests` and `CiWorkflowTests` read a workflow with.
///
/// New in row 10b, and it has no TypeScript counterpart: the TypeScript side
/// parsed workflows with the `yaml` npm package, which the zero-dependency
/// oracle cannot have. Same reasoning as the added `HarnessTests` case in row
/// 10a — a seam the oracle now owns is a seam the oracle has to pin, and a
/// parser that silently returned an empty mapping would turn every "this key is
/// absent" assertion into a pass having read nothing.
struct OracleYamlTests {
  static let workflow = """
  name: gate

  # a comment, and a blank line above it
  on:
    push:
    pull_request:

  jobs:
    build:
      runs-on: macos-15
      permissions:
        contents: read
      steps:
        - uses: actions/checkout@v4
        - name: build
          run: |
            set -euo pipefail
            # a colon: inside a block scalar is not a key
            swift build --package-path UseCasesCore
        - run: echo done
      tags:
        - "v1.2.3"
        - 'v1.2.3-rc1'
  """

  @Test
  func `a workflow's mappings, sequences, comments and block scalars all read back`() throws {
    let parsed = try OracleYaml.parse(Self.workflow)

    #expect(parsed["name"]?.stringValue == "gate")
    #expect(parsed["on"]?.sortedKeys == ["pull_request", "push"])

    let job = try #require(parsed["jobs"]?["build"])
    #expect(job["runs-on"]?.stringValue == "macos-15")
    #expect(job["permissions"]?["contents"]?.stringValue == "read")

    let steps = try #require(job["steps"]?.sequenceValue)
    #expect(steps.count == 3)
    #expect(steps[0]["uses"]?.stringValue == "actions/checkout@v4")
    #expect(steps[1]["name"]?.stringValue == "build")
    let script = try #require(steps[1]["run"]?.stringValue)
    #expect(script.contains("swift build --package-path UseCasesCore"))
    // A `key: value` line inside a block scalar is text, not structure.
    #expect(steps[1]["set"] == nil)
    #expect(steps[2]["run"]?.stringValue == "echo done")

    let tags = try #require(job["tags"]?.sequenceValue)
    #expect(tags == [.scalar("v1.2.3"), .scalar("v1.2.3-rc1")])
  }

  /// An absent key must be absent because it is not there, not because the
  /// reader gave up. Every negative assertion in the workflow suites rests on
  /// this.
  @Test
  func `a key that is not in the file reads as absent while its siblings read`() throws {
    let parsed = try OracleYaml.parse(Self.workflow)
    let push = try #require(parsed["on"])

    #expect(push["branches"] == nil)
    #expect(parsed["jobs"]?["build"]?["container"] == nil)
    // ...and the sibling that IS there still reads, so "absent" means absent.
    #expect(parsed["jobs"]?["build"]?["runs-on"]?.stringValue == "macos-15")
  }

  /// The forms a workflow never uses are REFUSED rather than half-read: a
  /// reader that skipped them would answer nil for a key that is present.
  @Test(arguments: [
    "on:\n  push:\n    branches: [main]\n",
    "jobs:\n  build:\n    env: { A: 1 }\n",
    "base: &anchor\n  runs-on: macos-15\n",
    "job:\n  runs-on: *anchor\n",
  ])
  func `a construct the reader does not understand is refused, never skipped`(source: String)
    throws
  {
    #expect(throws: OracleYaml.Failure.self) {
      try OracleYaml.parse(source)
    }
  }
}
