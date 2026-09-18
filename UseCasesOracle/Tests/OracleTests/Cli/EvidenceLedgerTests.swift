import Foundation
import Testing

/// The workspace the four evidence/ledger.yml suites build, at the scope
/// `evidence-ledger.test.ts` shares it.
enum EvidenceLedgerWorkspace {
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

  static func matrix(rows: [String]) -> String {
    let body = rows.map { name in
      """
        - id: probe.core.\(name)
          title: Row \(name)
          lifecycle: active
          value_tier: core
          journey_role: golden
          usage_frequency: common
          actor: agent
          intent: Exist so evidence can be recorded against it.
          preconditions: [Nothing.]
          trigger: Nothing.
          scenarios:
            - id: probe.core.\(name).golden_runs
              kind: steps
              steps: [Run it.]
              observable_outcomes: [It passes.]
          observable_outcomes: [It exists.]
          host_applicability:
            - host_surface: codex.cli
              supported: true
          verification_policy:
            mode: none
          approval_policy:
            mode: none

      """
    }.joined()
    return """
    schema_version: 1
    feature:
      id: probe.core
      name: Probe
      summary: Probe.
    use_cases:
    \(body)
    """
  }

  static func make(rows: [String] = ["alpha"]) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("evidence-ledger")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile("use-cases/probe.yml", contents: matrix(rows: rows))
    return directory
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      arguments,
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func record(
    _ directory: TemporaryDirectory,
    row: String,
    key: String,
    summary: String = "observed",
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "evidence", "record", "--repo", ".", "--use-case", "probe.core.\(row)",
      "--summary", summary, "--idempotency-key", key,
    ])
  }

  static func status(_ directory: TemporaryDirectory) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["evidence", "status", "--repo", "."])
  }

  static func aggregates(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data["aggregates"]?.arrayValue ?? []
  }

  /// The row's semantic hash as the matrix currently reports it.
  static func currentRowHash(
    _ directory: TemporaryDirectory,
    row: String,
  ) async throws -> String {
    let listed = try await run(directory, ["matrix", "list", "--repo", "."])
    let found = (listed.data["use_cases"]?.arrayValue ?? []).first { entry in
      entry["id"]?.stringValue == "probe.core.\(row)"
    }
    let row = try #require(found, Comment(rawValue: "probe.core.\(row) must be listed"))
    return try #require(row["semantic_hash"]?.stringValue)
  }

  static func retitle(
    _ directory: TemporaryDirectory,
    to title: String,
  ) throws {
    let text = try directory.readFile("use-cases/probe.yml")
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: text.replacingOccurrences(of: "title: Row alpha", with: title),
    )
  }

  static let tornLine = """
  {"schema_version":1,"event_type":"evidence_recorded","BROKEN

  """
}

/// The black-box oracle for evidence/ledger.yml, row `product_proof_map`.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct EvidenceLedgerProofMapTests {
  // golden_record. Proof is traceable from the event back to the row and the
  // hash of the row as it was when the evidence was taken.
  @Test
  func `evidence links to its use case and to the row's semantic hash`() async throws {
    let directory = try EvidenceLedgerWorkspace.make()
    let appended = try await EvidenceLedgerWorkspace.record(
      directory,
      row: "alpha",
      key: "first",
    )
    #expect(appended.isOk == true)

    let ledgerPath = try #require(appended.data["ledger_path"]?.stringValue)
    let stored = try OracleJson.parse(
      directory.readFile(ledgerPath).trimmingCharacters(in: .whitespacesAndNewlines),
    )

    #expect(stored.at("payload.targets.0.use_case_id")?.stringValue == "probe.core.alpha")
    let hash = try #require(stored.at("payload.targets.0.use_case_semantic_hash")?.stringValue)
    #expect(hash.hasPrefix("sha256:"))
  }

  // bad_hash_mismatch. A row that changed after its evidence was taken does not
  // keep the old proof.
  @Test
  func `evidence whose row hash no longer matches the row is detectably stale`()
    async throws
  {
    let directory = try EvidenceLedgerWorkspace.make()
    _ = try await EvidenceLedgerWorkspace.record(directory, row: "alpha", key: "first")

    // While nothing has changed, the hash the evidence was taken against IS the
    // row's current hash.
    let statused = try await EvidenceLedgerWorkspace.status(directory)
    let recorded = try #require(
      EvidenceLedgerWorkspace.aggregates(statused)
        .first?.at("target_links.0.use_case_semantic_hash")?.stringValue,
    )
    #expect(
      try await EvidenceLedgerWorkspace.currentRowHash(directory, row: "alpha") == recorded,
    )

    try EvidenceLedgerWorkspace.retitle(directory, to: "title: Row alpha, retitled")

    // After the edit the row moves and the evidence does not, which is what
    // makes the mismatch detectable rather than silent.
    let after = try await EvidenceLedgerWorkspace.status(directory)
    let stillRecorded = EvidenceLedgerWorkspace.aggregates(after)
      .first?.at("target_links.0.use_case_semantic_hash")?.stringValue
    #expect(stillRecorded == recorded, "the evidence keeps the hash it was taken against")
    let moved = try await EvidenceLedgerWorkspace.currentRowHash(directory, row: "alpha")
    #expect(
      moved != recorded,
      "a changed row must no longer match the hash its evidence carries",
    )
  }

  // bad_missing_row. A dangling link is reported, not silently dropped.
  @Test
  func `evidence naming a row that has left the matrix is reported`() async throws {
    let directory = try EvidenceLedgerWorkspace.make(rows: ["alpha", "beta"])
    _ = try await EvidenceLedgerWorkspace.record(directory, row: "beta", key: "first")

    let text = try directory.readFile("use-cases/probe.yml")
    let cut = try #require(text.range(of: "  - id: probe.core.beta"))
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: String(text[text.startIndex ..< cut.lowerBound]),
    )

    let statused = try await EvidenceLedgerWorkspace.status(directory)
    let reported = statused.data.encoded + statused.envelope.diagnostics.encoded
    #expect(
      reported.contains("probe.core.beta"),
      "the dangling target must surface somewhere",
    )
  }
}

/// The black-box oracle for evidence/ledger.yml, row
/// `append_only_corrections`.
struct EvidenceLedgerCorrectionsTests {
  // golden_void and edge_history_survives_the_correction.
  @Test
  func `a void is appended with the correct head, and the original survives`()
    async throws
  {
    let directory = try EvidenceLedgerWorkspace.make()
    let appended = try await EvidenceLedgerWorkspace.record(
      directory,
      row: "alpha",
      key: "first",
    )
    let ledgerPath = try #require(appended.data["ledger_path"]?.stringValue)
    let aggregate = try #require(appended.data.at("event.aggregate_id")?.stringValue)
    let eventIdentifier = try #require(appended.data.at("event.event_id")?.stringValue)
    let before = try directory.readFile(ledgerPath)

    let voided = try await EvidenceLedgerWorkspace.run(directory, [
      "evidence", "void", "--repo", ".", "--evidence", aggregate,
      "--expected-head", eventIdentifier, "--reason", "recorded against the wrong row",
    ])
    #expect(voided.isOk == true, Comment(rawValue: voided.standardOutput))

    let after = try directory.readFile(ledgerPath)
    #expect(after.hasPrefix(before), "the original event is never rewritten")
    let lineCount = after.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n").count
    let lineCountBefore = before.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n").count
    #expect(lineCount > lineCountBefore, "the void is appended")
  }

  // bad_wrong_head_is_refused. A correction cannot be applied to a ledger that
  // moved underneath it.
  @Test
  func `a void naming the wrong head is refused and writes nothing`() async throws {
    let directory = try EvidenceLedgerWorkspace.make()
    let appended = try await EvidenceLedgerWorkspace.record(
      directory,
      row: "alpha",
      key: "first",
    )
    let ledgerPath = try #require(appended.data["ledger_path"]?.stringValue)
    let aggregate = try #require(appended.data.at("event.aggregate_id")?.stringValue)
    let before = try directory.readFile(ledgerPath)

    let voided = try await EvidenceLedgerWorkspace.run(directory, [
      "evidence", "void", "--repo", ".", "--evidence", aggregate,
      "--expected-head", "evt_not_the_head", "--reason", "stale reader",
    ])
    #expect(voided.isOk == false)
    #expect(try directory.readFile(ledgerPath) == before)
  }
}

/// The black-box oracle for evidence/ledger.yml, row
/// `assurance_and_freshness`.
struct EvidenceLedgerAssuranceTests {
  // golden_assurance_class. The class reflects how the proof was CAPTURED, not
  // what it claims: a written summary is `reported` whatever it says.
  @Test
  func `a written summary is classed reported, however confident it reads`()
    async throws
  {
    let directory = try EvidenceLedgerWorkspace.make()
    _ = try await EvidenceLedgerWorkspace.record(
      directory,
      row: "alpha",
      key: "first",
      summary: "I ran the whole suite and everything passed",
    )

    let statused = try await EvidenceLedgerWorkspace.status(directory)
    let aggregate = try #require(EvidenceLedgerWorkspace.aggregates(statused).first)
    #expect(aggregate.at("assurance.class")?.stringValue == "reported")
    #expect(aggregate.at("assurance.capture_method")?.stringValue == "reported")
  }

  // bad_stale_is_not_reported_as_fresh and
  // golden_freshness_keeps_states_distinct.
  @Test
  func `the inputs freshness is judged from stop matching when the row moves`()
    async throws
  {
    let directory = try EvidenceLedgerWorkspace.make()
    _ = try await EvidenceLedgerWorkspace.record(directory, row: "alpha", key: "first")

    let statused = try await EvidenceLedgerWorkspace.status(directory)
    let inputs = try #require(
      EvidenceLedgerWorkspace.aggregates(statused).first?["freshness_inputs"],
    )
    #expect(inputs["explicit_invalidation"]?.boolValue == false)
    let hashes = (inputs["use_case_semantic_hashes"]?.arrayValue ?? []).compactMap { entry in
      entry.stringValue
    }
    let before = try await EvidenceLedgerWorkspace.currentRowHash(directory, row: "alpha")
    #expect(
      hashes.contains(before),
      "the hashes judged against are recorded, not inferred later",
    )

    try EvidenceLedgerWorkspace.retitle(directory, to: "title: Row alpha, moved on")

    let afterStatus = try await EvidenceLedgerWorkspace.status(directory)
    let afterHashes = (
      EvidenceLedgerWorkspace.aggregates(afterStatus)
        .first?.at("freshness_inputs.use_case_semantic_hashes")?.arrayValue ?? [],
    ).compactMap { entry in
      entry.stringValue
    }
    #expect(afterHashes == hashes, "the recorded inputs do not move with the row")
    let moved = try await EvidenceLedgerWorkspace.currentRowHash(directory, row: "alpha")
    #expect(
      !afterHashes.contains(moved),
      "so they no longer match the row, which is the staleness",
    )
  }
}

/// The black-box oracle for evidence/ledger.yml, row `damaged_ledger_replay`.
struct EvidenceLedgerDamageTests {
  // golden_partial. Valid events survive a damaged neighbour.
  @Test
  func `a torn line does not cost the valid events around it`() async throws {
    let directory = try EvidenceLedgerWorkspace.make()
    let first = try await EvidenceLedgerWorkspace.record(directory, row: "alpha", key: "first")
    _ = try await EvidenceLedgerWorkspace.record(directory, row: "alpha", key: "second")
    let statused = try await EvidenceLedgerWorkspace.status(directory)
    #expect(EvidenceLedgerWorkspace.aggregates(statused).count == 2)

    let ledgerPath = try #require(first.data["ledger_path"]?.stringValue)
    try directory.appendFile(ledgerPath, contents: EvidenceLedgerWorkspace.tornLine)

    let damaged = try await EvidenceLedgerWorkspace.status(directory)
    #expect(
      EvidenceLedgerWorkspace.aggregates(damaged).count == 2,
      "valid proof is not discarded because a neighbouring line is damaged",
    )
  }

  // bad_damage_is_never_silently_clean. Tolerating damage is not hiding it.
  @Test
  func `damage moves integrity off clean and is named in the diagnostics`()
    async throws
  {
    let directory = try EvidenceLedgerWorkspace.make()
    let first = try await EvidenceLedgerWorkspace.record(directory, row: "alpha", key: "first")
    let clean = try await EvidenceLedgerWorkspace.status(directory)
    #expect(clean.data.at("integrity.state")?.stringValue == "clean")

    let ledgerPath = try #require(first.data["ledger_path"]?.stringValue)
    try directory.appendFile(ledgerPath, contents: EvidenceLedgerWorkspace.tornLine)

    let damaged = try await EvidenceLedgerWorkspace.status(directory)
    #expect(damaged.isOk == false)
    #expect(
      damaged.data.at("integrity.state")?.stringValue == "partial",
      "damage is partial, never clean",
    )
    #expect(damaged.data.at("integrity.unknown_scope_damage")?.boolValue == true)
    #expect(damaged.envelope.diagnostics.encoded.contains("evidence_parse_error"))
  }
}
