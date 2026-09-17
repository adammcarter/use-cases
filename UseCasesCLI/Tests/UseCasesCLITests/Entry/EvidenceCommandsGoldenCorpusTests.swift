import Testing
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript evidence-command case — record (self-reported and
/// performed), status and void — replayed step by step through the Swift CLI:
/// each run's stdout, stderr and exit status, then every file left in the
/// sandbox, compared byte for byte after the numbering and masks
/// ``EvidenceEventNumbering`` and ``EvidenceCommandsMasking`` document.
struct EvidenceCommandsGoldenCorpusTests {
  @Test(arguments: EvidenceCommandsGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI and its ledgers byte for byte`(
    caseName: String,
  ) async throws {
    let recorded = try EvidenceCommandsFixtures.testCase(caseName)
    var sandbox = try EvidenceCommandsFixtures.Sandbox(recorded: recorded)

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

  static let voidEvent = #"{"event_type":"evidence_voided","event_id":"$EVENT2","#
    + #""intent_digest":""#

  static let maskCases: [(String, String)] = [
    (
      #"{"recorded_at":"2026-09-17T17:48:46.452Z","captured_at":"1970-01-01T00:00:00.000Z"}"#,
      #"{"recorded_at":"<timestamp>","captured_at":"1970-01-01T00:00:00.000Z"}"#,
    ),
    (
      voidEvent + "sha256:" + String(repeating: "ab", count: 32) + #"","x":1}"#,
      voidEvent + #"<void digest>","x":1}"#,
    ),
    (
      voidEvent + EvidenceCommandsMasking.zeroDigest + #""}"#,
      voidEvent + EvidenceCommandsMasking.zeroDigest + #""}"#,
    ),
    (
      #"{"event_type":"evidence_recorded","intent_digest":"sha256:"#
        + String(repeating: "ab", count: 32) + #""}"#,
      #"{"event_type":"evidence_recorded","intent_digest":"sha256:"#
        + String(repeating: "ab", count: 32) + #""}"#,
    ),
    (
      "    event_type: evidence_voided\n    event_id: $EVENT2\n    intent_digest: sha256:"
        + String(repeating: "cd", count: 32) + "\n",
      "    event_type: evidence_voided\n    event_id: $EVENT2\n    intent_digest: <void digest>\n",
    ),
  ]

  static let parseError = #"{"code":"evidence_parse_error","severity":"error","message":"#

  static let parseErrorCases: [(String, String)] = [
    (
      parseError + #""Unexpected token 'o', \"x\"","p":1}"#,
      parseError + #""<parser message>","p":1}"#,
    ),
    (
      #"{"code":"other","severity":"error","message":"kept"}"#,
      #"{"code":"other","severity":"error","message":"kept"}"#,
    ),
    (
      "  \u{2717} evidence_parse_error: Unexpected token 'o'\n      at evidence/x.jsonl:1\n",
      "  \u{2717} evidence_parse_error: <parser message>\n      at evidence/x.jsonl:1\n",
    ),
  ]

  @Test(arguments: parseErrorCases)
  func `masks the parser's own wording and nothing beside it`(
    input: String,
    expected: String,
  ) {
    #expect(EvidenceCommandsMasking.masked(input) == expected)
  }

  @Test(arguments: maskCases)
  func `masks only wall-clock timestamps and void digests`(
    input: String,
    expected: String,
  ) {
    #expect(EvidenceCommandsMasking.masked(input) == expected)
  }

  @Test
  func `numbers event ids by first appearance and binds them back`() {
    let first = "01a0b07c-39f4-7d07-8840-ec884c7cb6d0"
    let second = "01a0b07c-3aa8-7647-8613-04aab7c13f55"
    var numbering = EvidenceEventNumbering()

    let numbered = numbering.numbered("\(second) \(first) \(second)")

    #expect(numbered == "$EVENT1 $EVENT2 $EVENT1")
    #expect(numbering.concrete("--evidence $EVENT2") == "--evidence \(first)")
  }
}
