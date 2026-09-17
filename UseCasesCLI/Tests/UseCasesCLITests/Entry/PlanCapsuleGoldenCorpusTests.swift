import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript plan- and capsule-command case — `plan showcase`,
/// `plan walkthrough`, `plan cards` and `capsule list|validate|plan|run` —
/// replayed step by step through the Swift CLI: each run's stdout, stderr and
/// exit status, then every file left in the sandbox, compared byte for byte
/// after the masks ``PlanCapsuleMasking`` documents.
struct PlanCapsuleGoldenCorpusTests {
  @Test(arguments: PlanCapsuleGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI and its runs byte for byte`(
    caseName: String,
  ) async throws {
    let recorded = try PlanCapsuleFixtures.testCase(caseName)
    let sandbox = try PlanCapsuleFixtures.Sandbox(recorded: recorded)

    let runs = try await sandbox.replay()

    try #require(runs.count == recorded["runs"]?.arrayValue?.count)
    for (index, run) in runs.enumerated() {
      let step = run.arguments.joined(separator: " ")
      #expect(
        try run.standardOutput == (sandbox.expected("stdout", ofRun: index)),
        "stdout of step \(index): \(step)",
      )
      #expect(
        try run.standardError == (sandbox.expected("stderr", ofRun: index)),
        "stderr of step \(index): \(step)",
      )
      let expectedStatus = try sandbox.expectedRun(index)["status"]?.numberValue ?? -1
      #expect(run.exitCode == Int32(expectedStatus), "exit code of step \(index): \(step)")
    }
    #expect(try sandbox.actualTree() == sandbox.expectedTree())
  }

  /// A 64-digit run of zeros: the working-tree digest every envelope carries,
  /// which must survive the epoch mask untouched.
  static let zeroes = String(repeating: "0", count: 64)

  static let maskCases: [(String, String)] = [
    (
      #"{"run_id":"run.capsule_capsule_probe_tour_1789671553755_start"}"#,
      #"{"run_id":"run.capsule_capsule_probe_tour_<epoch>_start"}"#,
    ),
    (
      #"{"idempotency_key":"capsule:capsule.probe.tour:1789671553755:start"}"#,
      #"{"idempotency_key":"capsule:capsule.probe.tour:<epoch>:start"}"#,
    ),
    (
      #"{"working_tree_digest":"sha256:"# + zeroes + #""}"#,
      #"{"working_tree_digest":"sha256:"# + zeroes + #""}"#,
    ),
    (
      #"{"code":"parse_error","severity":"error","message":"Tabs are not allowed"}"#,
      #"{"code":"parse_error","severity":"error","message":"<parser message>"}"#,
    ),
    (
      #"{"code":"other","severity":"error","message":"kept"}"#,
      #"{"code":"other","severity":"error","message":"kept"}"#,
    ),
    (
      "  \u{2717} parse_error: Tabs are not allowed as indentation\n      at x.yml:2\n",
      "  \u{2717} parse_error: <parser message>\n      at x.yml:2\n",
    ),
    (
      #""message":"Presentation plan file could not be read: Unexpected token 'o'""#,
      #""message":"Presentation plan file could not be read: <parser message>""#,
    ),
    (
      #""message":"Presentation plan file could not be read: ENOENT: no such file, open 'x'""#,
      #""message":"Presentation plan file could not be read: ENOENT: no such file, open 'x'""#,
    ),
    (
      #""message":"Presentation plan file could not be read: EISDIR: illegal operation""#,
      #""message":"Presentation plan file could not be read: EISDIR: illegal operation""#,
    ),
  ]

  @Test(arguments: maskCases)
  func `masks only a derived run's epoch and the parsers' own wording`(
    input: String,
    expected: String,
  ) {
    #expect(PlanCapsuleMasking.masked(input) == expected)
  }
}
