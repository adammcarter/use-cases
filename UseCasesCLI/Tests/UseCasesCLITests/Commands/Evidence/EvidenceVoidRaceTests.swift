import Foundation
import Testing
import TestSupport
import UseCasesCore

/// Eight separate `use-cases` processes voiding the SAME evidence at once —
/// the cross-process guarantee ADR 0007 decision 10 makes, and the only shape
/// of contention that can reveal a broken append lock: each evidence aggregate
/// lives in its own ledger file, so writers recording DIFFERENT events never
/// contend (docs/rewrite/ladder-notes.md, row 4).
///
/// With the lock, exactly one process appends the void and the other seven are
/// refused `evidence_invalid_transition` — the status check fires before the
/// idempotency check, so the losers are not deduplicated into a silent
/// success — and the history replays clean afterwards.
///
/// Measured with the lock disabled (`withAppendLock` calling its work
/// directly): all eight processes appended, on three of three runs, and replay
/// then reported `evidence_sequence_conflict` — so this test can fail.
struct EvidenceVoidRaceTests {
  static let writerCount = 8

  /// Extra evidence ledgers seeded before the race, to make it a sound check
  /// rather than a lucky one.
  ///
  /// Every writer replays the whole history before it appends, and the window
  /// the lock protects is that replay. With an almost empty history a replay
  /// takes under a millisecond — less than the time to launch the next
  /// process — so even an unlocked appender usually sees the first void and
  /// refuses, and the mutation passes by luck (the row 3e note reports the
  /// same thing in-process). Four hundred ledgers make a replay some tens of
  /// milliseconds, wider than the launch stagger, so every writer reads the
  /// same state: measured with the lock disabled, all eight then append.
  static let seededLedgerCount = 400

  @Test(arguments: [1, 2, 3])
  func `exactly one of eight processes voids the same evidence`(attempt: Int) async throws {
    let binary = try UseCasesBinary.located()
    let directory = try TemporaryDirectory()
    let root = directory.url.path
    _ = try directory.makeDirectory("home")
    _ = try directory.makeDirectory("runs")
    try directory.writeFile("use-cases.yml", contents: Self.configuration)
    try directory.writeFile("use-cases/probe.yml", contents: Self.matrix)
    let environment = UseCasesBinary.environment(home: root + "/home")

    let recorded = try await binary.run(
      arguments: ["evidence", "record", "--repo", root, "--use-case", "probe.core.alpha", "--json"],
      environment: environment,
      outputDirectory: root + "/runs",
      label: "record-\(attempt)",
    )
    try #require(
      recorded.exitCode == 0,
      Comment(rawValue: recorded.standardOutput + recorded.standardError),
    )
    let event = try Self.recordedEvent(in: recorded.standardOutput)
    let evidenceIdentifier = try #require(event["event_id"]?.stringValue)
    try Self.seedLedgers(under: root, like: event)

    let outcomes = try await Self.raceVoids(
      binary,
      of: evidenceIdentifier,
      root: root,
      environment: environment,
      attempt: attempt,
    )

    try #require(outcomes.count == Self.writerCount)
    let winners = outcomes.filter { outcome in
      outcome.exitCode == 0 && outcome.standardOutput.contains(#""appended":true"#)
    }
    let losers = outcomes.filter { outcome in
      outcome.exitCode == 6
        && outcome.standardOutput.contains(#""code":"evidence_invalid_transition""#)
    }
    #expect(winners.count == 1, Self.report(outcomes))
    #expect(losers.count == Self.writerCount - 1, Self.report(outcomes))

    let replayed = try await binary.run(
      arguments: ["evidence", "status", "--repo", root, "--json"],
      environment: environment,
      outputDirectory: root + "/runs",
      label: "status-\(attempt)",
    )
    Self.expectCleanReplay(replayed)
  }

  /// ``writerCount`` voids of the same evidence, every one of them started
  /// before any is waited for.
  static func raceVoids(
    _ binary: UseCasesBinary,
    of evidenceIdentifier: String,
    root: String,
    environment: [String: String],
    attempt: Int,
  ) async throws -> [UseCasesProcess.Outcome] {
    var writers: [UseCasesProcess] = []
    for writer in 0 ..< writerCount {
      try writers.append(binary.started(
        arguments: [
          "evidence", "void",
          "--repo", root,
          "--evidence", evidenceIdentifier,
          "--expected-head", evidenceIdentifier,
          "--reason", "raced by writer \(writer)",
          "--json",
        ],
        environment: environment,
        outputDirectory: root + "/runs",
        label: "void-\(attempt)-\(writer)",
      ))
    }
    var outcomes: [UseCasesProcess.Outcome] = []
    for writer in writers {
      try await outcomes.append(writer.outcome())
    }
    return outcomes
  }

  /// The history after the race: no sequence conflict, and exactly one record,
  /// one void and every seeded ledger — no void lost, none written twice.
  static func expectCleanReplay(_ replayed: UseCasesProcess.Outcome) {
    let output = replayed.standardOutput
    #expect(replayed.exitCode == 0)
    #expect(!output.contains("evidence_sequence_conflict"), Comment(rawValue: output))
    #expect(output.contains(#""complete":true"#), Comment(rawValue: output))
    #expect(
      output.contains(#""events_loaded":\#(seededLedgerCount + 2)"#),
      Comment(rawValue: output),
    )
    #expect(output.contains(#""aggregates_invalid":0"#), Comment(rawValue: output))
  }

  /// Every outcome, so a failure says what the eight processes actually did.
  static func report(_ outcomes: [UseCasesProcess.Outcome]) -> Comment {
    Comment(rawValue: outcomes.map { outcome in
      "exit \(outcome.exitCode): \(outcome.standardOutput)"
    }.joined(separator: "\n"))
  }

  /// The appended event, whose `event_id` is also its aggregate id.
  static func recordedEvent(in output: String) throws -> JSONObject {
    let envelope = try JSONParser.parse(output)
    return try #require(
      envelope["data"]?["event"]?.objectValue,
      Comment(rawValue: output),
    )
  }

  /// ``seededLedgerCount`` more aggregates, each a copy of the recorded event
  /// under its own id and idempotency key, in the ledger its id names.
  static func seedLedgers(
    under root: String,
    like event: JSONObject,
  ) throws {
    let directory = root + "/evidence/by-id/se"
    try FileManager.default.createDirectory(
      atPath: directory,
      withIntermediateDirectories: true,
    )
    for index in 0 ..< seededLedgerCount {
      let identifier = "seed-" + String(format: "%05d", index)
      var seeded = event
      seeded["event_id"] = .string(identifier)
      seeded["aggregate_id"] = .string(identifier)
      seeded["idempotency_key"] = .string("seed:\(index)")
      let line = JSONWriter.encode(.object(seeded)) + "\n"
      try #require(FileManager.default.createFile(
        atPath: "\(directory)/\(identifier).jsonl",
        contents: Data(line.utf8),
      ))
    }
  }

  static let configuration = """
  schema_version: 1
  workspace_id: probe
  component_id: probe
  data_root: .
  use_cases_dir: use-cases
  evidence_dir: evidence
  demo_capsules_dir: demo-capsules
  showcase_runs_dir: showcase-runs
  default_workflow_mode: continuous

  """

  static let matrix = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.alpha
      title: Alpha
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so evidence can be recorded and voided against it.
      preconditions: [Nothing.]
      trigger: An agent records evidence.
      scenarios:
        - id: probe.core.alpha.golden_runs
          kind: steps
          steps: [Record it, then void it.]
          observable_outcomes: [One void is appended.]
      observable_outcomes: [A JSONL event is appended under evidence.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """
}
