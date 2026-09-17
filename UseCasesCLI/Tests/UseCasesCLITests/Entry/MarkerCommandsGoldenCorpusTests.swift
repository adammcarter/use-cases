import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// Every recorded TypeScript marker-command case — bind, unbind, rebind, scan,
/// impact, prove, verify, validate-ledger, keygen and recover — replayed step
/// by step through the Swift CLI: each run's stdout, stderr and exit status,
/// then every file left in the sandbox, compared byte for byte after the masks
/// ``MarkerCommandsMasking`` documents.
struct MarkerCommandsGoldenCorpusTests {
  @Test(arguments: MarkerCommandsGoldenCorpus.caseNames)
  func `reproduces the TypeScript CLI, its ledgers and its files byte for byte`(
    caseName: String,
  ) throws {
    let recorded = try MarkerCommandsFixtures.testCase(caseName)
    let sandbox = try MarkerCommandsFixtures.Sandbox(recorded: recorded)

    let runs = try sandbox.replay()

    try #require(runs.count == recorded["runs"]?.arrayValue?.count)
    for (index, run) in runs.enumerated() {
      let isKeygen = run.arguments.first == "keygen"
      let expectedOutput = try sandbox.expected("stdout", ofRun: index)
      let format: MarkerCommandsMasking.Format = expectedOutput.hasPrefix("{") ? .json : .text
      let mask = { (text: String) in
        let masked = MarkerCommandsMasking.masked(
          text,
          format: format,
          attestationsVary: sandbox.attestationsVary,
        )
        return isKeygen ? MarkerCommandsMasking.withoutMintedKeys(masked) : masked
      }
      #expect(
        mask(run.outcome.standardOutput) == mask(expectedOutput),
        "stdout of step \(index): \(run.arguments.joined(separator: " "))",
      )
      let expectedError = try sandbox.expected("stderr", ofRun: index)
      let expectedStatus = try sandbox.expectedRun(index)["status"]?.numberValue ?? -1
      #expect(
        mask(run.outcome.standardError) == mask(expectedError),
        "stderr of step \(index): \(run.arguments.joined(separator: " "))",
      )
      #expect(
        run.outcome.exitCode == Int32(expectedStatus),
        "exit code of step \(index): \(run.arguments.joined(separator: " "))",
      )
    }
    #expect(try sandbox.actualTree() == sandbox.expectedTree())
  }

  static let hashKey = #""previous_entry_hash":"sha256:"#
  static let zeroHash = hashKey + String(repeating: "0", count: 64) + "\""
  static let chainedHash = hashKey + String(repeating: "1", count: 64) + "\""
  static let parserWorded: String = #"{"message":"line 1 is not valid JSON: Unexpected token 'o', "#
    + #"\"not json\" is not valid JSON","x":1}"#

  static let maskCases: [(String, String)] = [
    (
      #"{"event_id":"01K2O4NVAF8E6WYNP06CAGD4MT","created_at":"2026-09-17T16:56:05.199Z"}"#,
      #"{"event_id":"<event id>","created_at":"<timestamp>"}"#,
    ),
    (
      #"{"created_at":"2026-09-17T12:00:00.000Z","captured_at":"1970-01-01T00:00:00.000Z"}"#,
      #"{"created_at":"2026-09-17T12:00:00.000Z","captured_at":"1970-01-01T00:00:00.000Z"}"#,
    ),
    ("      event_id: 01K2O4QHJ8PHRS53QX43F7MV3D\n", "      event_id: <event id>\n"),
    (zeroHash, zeroHash),
    (chainedHash, #""previous_entry_hash":"<hash>""#),
    (parserWorded, #"{"message":"line 1 is not valid JSON: <parser message>","x":1}"#),
  ]

  @Test(arguments: maskCases)
  func `masks only what is nondeterministic or parser-worded`(
    input: String,
    expected: String,
  ) {
    #expect(MarkerCommandsMasking.masked(input, format: .json, attestationsVary: false) == expected)
  }

  @Test
  func `masks human parser wording to the end of its line`() {
    let input = "      message: line 1 is not valid JSON: Unexpected token 'o', \"x\"\nnext\n"

    let masked = MarkerCommandsMasking.masked(input, format: .text, attestationsVary: false)

    #expect(masked == "      message: line 1 is not valid JSON: <parser message>\nnext\n")
  }

  @Test
  func `masks minted keys in raw and JSON-escaped text alike`() {
    let raw = "-----BEGIN PRIVATE KEY-----\nMC4CAQAw=\n-----END PRIVATE KEY-----"
    let escaped = #"-----BEGIN PUBLIC KEY-----\nMCowBQ=\n-----END PUBLIC KEY-----"#

    #expect(
      MarkerCommandsMasking.withoutMintedKeys(raw)
        == "-----BEGIN PRIVATE KEY-----\n<minted>\n-----END PRIVATE KEY-----",
    )
    #expect(
      MarkerCommandsMasking.withoutMintedKeys(escaped)
        == #"-----BEGIN PUBLIC KEY-----\n<minted>\n-----END PUBLIC KEY-----"#,
    )
  }
}
