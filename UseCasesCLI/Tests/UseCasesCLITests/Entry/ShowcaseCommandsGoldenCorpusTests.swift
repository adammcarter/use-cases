import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript showcase case — the twelve `showcase` verbs and
/// `approve-run` — replayed step by step through the Swift CLI: each run's
/// stdout, stderr and exit status, then every file left in the sandbox,
/// compared byte for byte after the masks ``ShowcaseCommandsMasking``
/// documents.
struct ShowcaseCommandsGoldenCorpusTests {
  @Test(arguments: ShowcaseCommandsGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI and its run ledgers byte for byte`(
    caseName: String,
  ) async throws {
    let recorded = try ShowcaseCommandsFixtures.testCase(caseName)
    var sandbox = try ShowcaseCommandsFixtures.Sandbox(recorded: recorded)

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

  static let approvalEvent = #"{"event_type":"approval_recorded","event_id":"evt.run.s1.8","#
    + #""intent_digest":""#
  static let verdictEvent = #"{"event_type":"verdict_recorded","event_id":"evt.run.s1.3","#
    + #""intent_digest":""#
  static let signature = String(repeating: "Ab+/", count: 22)

  static let maskCases: [(String, String)] = [
    (
      #"{"jti":"approval.dbfa05c1-74c7-432a-bfe0-08d214e5e469"}"#,
      #"{"jti":"approval.<nonce>"}"#,
    ),
    (
      "  nonce approval.40325fe9-50f0-4e98-9baf-df43432cddc2\n",
      "  nonce approval.<nonce>\n",
    ),
    (
      "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIA==\n-----END PRIVATE KEY-----\n",
      "-----BEGIN PRIVATE KEY-----\n<pem>\n-----END PRIVATE KEY-----\n",
    ),
    (
      #""public_key": "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA\n-----END PUBLIC KEY-----\n""#,
      #""public_key": "-----BEGIN PUBLIC KEY-----\n<pem>\n-----END PUBLIC KEY-----\n""#,
    ),
    (
      #"{"alg":"ed25519","value":""# + signature + #""}"#,
      #"{"alg":"ed25519","value":"<signature>"}"#,
    ),
    (
      #"{"alg": "ed25519", "value": ""# + signature + #""}"#,
      #"{"alg": "ed25519", "value": "<signature>"}"#,
    ),
    (
      approvalEvent + "sha256:" + String(repeating: "ab", count: 32) + #"","x":1}"#,
      approvalEvent + #"<approval digest>","x":1}"#,
    ),
    (
      verdictEvent + "sha256:" + String(repeating: "cd", count: 32) + #"","x":1}"#,
      verdictEvent + "sha256:" + String(repeating: "cd", count: 32) + #"","x":1}"#,
    ),
    (
      "    event_type: approval_recorded\n    intent_digest: sha256:"
        + String(repeating: "ef", count: 32) + "\n",
      "    event_type: approval_recorded\n    intent_digest: <approval digest>\n",
    ),
    (
      "    event_type: verdict_recorded\n    intent_digest: sha256:"
        + String(repeating: "ef", count: 32) + "\n",
      "    event_type: verdict_recorded\n    intent_digest: sha256:"
        + String(repeating: "ef", count: 32) + "\n",
    ),
    (
      #"{"recorded_at":"2026-06-25T12:01:00.000Z","captured_at":"2026-09-17T19:11:14.810Z"}"#,
      #"{"recorded_at":"2026-06-25T12:01:00.000Z","captured_at":"<timestamp>"}"#,
    ),
    (
      #"{"captured_at":"1970-01-01T00:00:00.000Z"}"#,
      #"{"captured_at":"1970-01-01T00:00:00.000Z"}"#,
    ),
    (
      #""message":"could not read/parse --request: Unexpected token 'o'""#,
      #""message":"could not read/parse --request: <parser message>""#,
    ),
    (
      #""message":"could not read/parse --keyring: ENOENT: no such file, open 'x'""#,
      #""message":"could not read/parse --keyring: ENOENT: no such file, open 'x'""#,
    ),
  ]

  @Test(arguments: maskCases)
  func `masks only minted key material, nonces and wall-clock stamps`(
    input: String,
    expected: String,
  ) {
    #expect(ShowcaseCommandsMasking.masked(input) == expected)
  }
}
