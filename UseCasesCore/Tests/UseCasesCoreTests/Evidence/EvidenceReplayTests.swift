import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Reading `evidence/**/*.jsonl` and replaying it, against what the TypeScript
/// returned for the same tree: ledgers in order, every event, every diagnostic
/// in order, every aggregate and the wire status result — or the error it
/// threw instead.
struct EvidenceReplayTests {
  @Test(arguments: EvidenceGoldenCorpus.readCaseNames)
  func `a tree reads exactly as the TypeScript read it`(caseName: String) throws {
    let testCase = try EvidenceFixtures.goldenCase(caseName, in: "read")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()

    let outcome = Result { () throws(EvidenceEventError) -> EvidenceLedgerReadResult in
      try EvidenceLedgerReader.read(context: context)
    }

    if let thrown = testCase["read_throws"] {
      guard case let .failure(error) = outcome else {
        Issue.record("expected reading to throw \(EvidenceFixtures.wire(thrown))")
        return
      }
      EvidenceFixtures.expectThrown(error, equals: thrown, in: workspace)
      return
    }
    try EvidenceFixtures.expectMembers(
      of: testCase["read"],
      equal: EvidenceFixtures.readRecord(outcome.get()),
      in: workspace,
    )
  }

  @Test(arguments: EvidenceGoldenCorpus.readCaseNames)
  func `a tree replays exactly as the TypeScript replayed it`(caseName: String) throws {
    let testCase = try EvidenceFixtures.goldenCase(caseName, in: "read")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()

    let outcome = Result { () throws(EvidenceEventError) -> EvidenceSnapshot in
      try EvidenceReplay.replay(context: context)
    }

    if let thrown = testCase["replay_throws"] {
      guard case let .failure(error) = outcome else {
        Issue.record("expected replay to throw \(EvidenceFixtures.wire(thrown))")
        return
      }
      EvidenceFixtures.expectThrown(error, equals: thrown, in: workspace)
      return
    }
    try EvidenceFixtures.expectMembers(
      of: testCase["replay"],
      equal: EvidenceFixtures.snapshotRecord(outcome.get()),
      in: workspace,
    )
  }
}

/// The reading behaviours the brief names, each pinned on its own so a failure
/// names the behaviour rather than a corpus case.
struct EvidenceLedgerReadingEdgeTests {
  private func replay(_ caseName: String) throws
    -> (Result<EvidenceSnapshot, EvidenceEventError>, JSONValue)
  {
    let testCase = try EvidenceFixtures.goldenCase(caseName, in: "read")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()
    let outcome = Result { () throws(EvidenceEventError) -> EvidenceSnapshot in
      try EvidenceReplay.replay(context: context)
    }
    return (outcome, testCase)
  }

  @Test
  func `invalid UTF-8 throws node's decoding error rather than becoming a diagnostic`() throws {
    let (outcome, _) = try replay("invalid_utf8_throws")

    #expect(throws: EvidenceEventError.invalidEncoding) {
      try outcome.get()
    }
    #expect(EvidenceEventError.invalidEncoding.code == "ERR_ENCODING_INVALID_ENCODED_DATA")
  }

  @Test
  func `a symlinked ledger is skipped without a diagnostic`() throws {
    let (outcome, _) = try replay("symlinked_ledgers_and_directories_are_skipped")
    let snapshot = try outcome.get()

    #expect(snapshot.ledgers.map(\.path) == ["evidence/by-id/ev/ev-real.jsonl"])
    #expect(snapshot.diagnostics.isEmpty)
  }

  @Test
  func `a missing evidence directory is an empty, complete history`() throws {
    let (outcome, _) = try replay("no_evidence_directory")
    let snapshot = try outcome.get()

    #expect(snapshot.isComplete)
    #expect(snapshot.ledgers.isEmpty)
    #expect(snapshot.integrity.state == .clean)
  }

  @Test
  func `CRLF endings read as one clean event and blank lines are skipped`() throws {
    let crlf = try replay("crlf_line_endings").0.get()
    let blank = try replay("blank_and_whitespace_lines_are_skipped").0.get()

    #expect(crlf.isComplete && crlf.events.count == 1)
    #expect(blank.isComplete && blank.events.count == 1)
  }

  @Test
  func `diagnostics keep line order within a ledger`() throws {
    let (outcome, testCase) = try replay("parse_errors_and_foreign_lines")
    let snapshot = try outcome.get()

    let expected = try #require(testCase["replay"]?["diagnostics"]?.arrayValue)
      .compactMap { $0["source_path"]?.stringValue }
    #expect(snapshot.diagnostics.compactMap(\.sourcePath) == expected)
    #expect(snapshot.diagnostics.first?.sourcePath == "evidence/by-id/ev/ev-mixed.jsonl:1")
  }

  @Test
  func `ledgers are listed in code unit order after a locale ordered walk`() throws {
    let (outcome, _) = try replay("walk_is_locale_but_final_order_is_code_unit")
    let paths = try outcome.get().ledgers.map(\.path)

    #expect(paths.prefix(4) == [
      "evidence/-x.jsonl",
      "evidence/B.jsonl",
      "evidence/Z/inner.jsonl",
      "evidence/_x.jsonl",
    ])
  }

  /// The TypeScript throws a `TypeError` here and the process dies with it. A
  /// Swift process cannot read a property of null, so the same failure is a
  /// typed error carrying V8's exact message and the precedent's code
  /// `unreadable_event` (see ``ProofSignatureError/unreadableEvent``). What
  /// differs: the TypeScript error has no `code` at all.
  @Test(arguments: [
    ("malformed_targets_string_throws", "((intermediate value) ?? []).map is not a function"),
    (
      "malformed_null_target_throws",
      "Cannot read properties of null (reading 'use_case_semantic_hash')"
    ),
    ("malformed_use_case_ids_throws", "(payload.use_case_ids ?? []).map is not a function"),
  ])
  func `a malformed event the TypeScript crashes on is a typed error with V8's message`(
    caseName: String,
    message: String,
  ) throws {
    let (outcome, testCase) = try replay(caseName)

    #expect(testCase["replay_throws"]?["message"] == .string(message))
    #expect(throws: EvidenceEventError.unreadableEvent(message: message)) {
      try outcome.get()
    }
    #expect(EvidenceEventError.unreadableEvent(message: message).code == "unreadable_event")
  }

  @Test
  func `a non-finite number compared as a duplicate throws canonical JSON's error`() throws {
    let (outcome, _) = try replay("non_finite_number_in_duplicate_throws")

    #expect(throws: EvidenceEventError.nonFiniteNumber) {
      try outcome.get()
    }
  }
}
