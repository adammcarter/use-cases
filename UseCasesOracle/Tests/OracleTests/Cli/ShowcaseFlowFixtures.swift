import CryptoKit
import Foundation
import Testing

/// The workspace, verbs and ledger readers the showcase/flow.yml suites share,
/// at the scope `showcase-flow.test.ts` shares them: module scope inside one
/// oracle file.
///
/// Everything here talks ONLY to the CLI binary: no core import, no internal
/// call. Each test builds its own throwaway workspace, so nothing depends on a
/// fixture a later change might reshape. UC_RUN_KEY_FILE always points at a
/// throwaway path inside the temp dir, so no test reads or writes the
/// developer's own machine key.
///
/// One finding surfaced while writing the TypeScript original and is carried
/// here: `showcase.flow.revision_epoch_staleness` names a real core capability
/// (appendShowcaseEpoch, and replay understands epoch_started events) but NO
/// CLI command appends one. That whole row is disabled tests, not faked ones.
///
/// A second, smaller finding: `showcase start` always records control_mode
/// agent_led and `record-observation` always records actor agent. Only
/// `record-verdict`'s --actor varies who is credited, so "choose the control
/// mode for each item" is only reachable at the verdict layer through this
/// binary.
enum ShowcaseWorkspace {
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

  static let requireUserApproval = """
      approval_policy:
        mode: predefined
        requirements:
          - approver_type: user
            minimum_count: 1
        statement: User accepts the demonstrated showcase scope.
  """

  static let noApproval = """
      approval_policy:
        mode: none
  """

  /// A row with `verification_policy.mode: none` is not selectable for a plan
  /// (measured: it yields an empty selection), so every fixture row carries a
  /// real requirements policy — mode: requirements, evidence_kind: live_demo,
  /// required_verifiers: [user] — exactly as showcase rows are meant to.
  static func singleRowFeatureFile(approvalPolicy: String) -> String {
    """
    schema_version: 1
    feature:
      id: probe.showcase
      name: Probe showcase
      summary: A behaviour proved live through showcase start/observe/verdict/finish.
    use_cases:
      - id: probe.showcase.thing
        title: The thing works
        lifecycle: active
        value_tier: critical
        journey_role: golden
        usage_frequency: common
        actor: agent
        intent: Prove one scenario end to end through a live showcase run.
        preconditions: [A source file exists.]
        trigger: An agent demonstrates the behaviour live.
        scenarios:
          - id: probe.showcase.thing.golden_runs
            kind: steps
            steps: [Run it live.]
            observable_outcomes: [It works.]
        observable_outcomes: [The row is demonstrated live.]
        host_applicability:
          - host_surface: codex.cli
            supported: true
        verification_policy:
          mode: requirements
          requirements:
            - evidence_kind: live_demo
              required_verifiers: [user]
              minimum_count: 1
    \(approvalPolicy)

    """
  }

  static func make(approvalPolicy: String = noApproval) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("blackbox-showcase")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: singleRowFeatureFile(approvalPolicy: approvalPolicy),
    )
    return directory
  }

  /// A two-row fixture, needed only by the correction test: `showcase start
  /// --adhoc` selects exactly one item (--select takes a single id), so a run
  /// with more than one item has to go through `plan showcase` → a plan file.
  static func makeMultiItem() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("blackbox-showcase-multi")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    let row = { (identifier: String, title: String) in
      """
        - id: probe.showcase.\(identifier)
          title: \(title)
          lifecycle: active
          value_tier: critical
          journey_role: golden
          usage_frequency: common
          actor: agent
          intent: Prove \(identifier).
          preconditions: [A source file exists.]
          trigger: An agent demonstrates the behaviour live.
          scenarios:
            - id: probe.showcase.\(identifier).golden_runs
              kind: steps
              steps: [Run it live.]
              observable_outcomes: [It works.]
          observable_outcomes: [The row is demonstrated live.]
          host_applicability:
            - host_surface: codex.cli
              supported: true
          verification_policy:
            mode: requirements
            requirements:
              - evidence_kind: live_demo
                required_verifiers: [user]
                minimum_count: 1
          approval_policy:
            mode: none

      """
    }
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: """
      schema_version: 1
      feature:
        id: probe.showcase
        name: Probe showcase
        summary: Two rows so one run can carry two independent failures.
      use_cases:
      \(row("alpha", "Alpha works"))\(row("beta", "Beta works"))
      """,
    )
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

  static func start(
    _ directory: TemporaryDirectory,
    key: String,
    useCase: String = "probe.showcase.thing",
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "start", "--repo", ".", "--adhoc", "--select", useCase,
      "--idempotency-key", key,
    ])
  }

  static func startedRunIdentifier(
    _ directory: TemporaryDirectory,
    key: String,
  ) async throws -> String {
    let started = try await start(directory, key: key)
    #expect(started.isOk == true, Comment(rawValue: started.standardOutput))
    return try #require(started.data["run_id"]?.stringValue)
  }

  static func observe(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    item: String,
    text: String,
    key: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "record-observation", "--repo", ".", "--run", runIdentifier,
      "--item", item, "--text", text, "--idempotency-key", key,
    ])
  }

  static func verdict(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    item: String,
    verdict value: String,
    key: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "record-verdict", "--repo", ".", "--run", runIdentifier,
      "--item", item, "--verdict", value, "--idempotency-key", key,
    ])
  }

  /// The same verb with `--actor`, which only `performUnderActor` needs. Kept
  /// separate so neither signature carries six parameters.
  static func verdict(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    pass item: String,
    key: String,
    actor: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "record-verdict", "--repo", ".", "--run", runIdentifier,
      "--item", item, "--verdict", "pass", "--idempotency-key", key,
      "--actor", actor,
    ])
  }

  /// A failure decision: what was decided, and why.
  struct Decision {
    let kind: String
    let reason: String
  }

  static func decide(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    verdictEvent: String,
    decision: Decision,
    key: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "decide", "--repo", ".", "--run", runIdentifier,
      "--verdict-event", verdictEvent, "--decision", decision.kind,
      "--reason", decision.reason, "--idempotency-key", key,
    ])
  }

  /// A correction: the verdict it replaces the old one with, and why.
  struct Correction {
    let verdict: String
    let reason: String
  }

  static func correct(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    targetEvent: String,
    correction: Correction,
    key: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "showcase", "correct", "--repo", ".", "--run", runIdentifier,
      "--target-event", targetEvent, "--verdict", correction.verdict,
      "--reason", correction.reason, "--idempotency-key", key,
    ])
  }

  static func finish(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["showcase", "finish", "--repo", ".", "--run", runIdentifier])
  }

  static func status(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    extra: [String] = [],
  ) async throws -> OracleJson {
    try await run(
      directory,
      ["showcase", "status", "--repo", ".", "--run", runIdentifier] + extra,
    ).data
  }
}

/// The ledger readers and the composed flows, split out so neither body runs
/// past the length a reviewer can hold in their head.
extension ShowcaseWorkspace {
  static func runDirectory(_ runIdentifier: String) -> String {
    "showcase-runs/\(runIdentifier)"
  }

  static func eventsPath(_ runIdentifier: String) -> String {
    "showcase-runs/\(runIdentifier)/events.jsonl"
  }

  static func readEvents(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
  ) throws -> [OracleJson] {
    try directory.readFile(eventsPath(runIdentifier))
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .compactMap { line in
        try? OracleJson.parse(String(line))
      }
  }

  static func event(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    ofType type: String,
  ) throws -> OracleJson? {
    try readEvents(directory, run: runIdentifier).first { event in
      event["event_type"]?.stringValue == type
    }
  }

  static func items(_ status: OracleJson) -> [OracleJson] {
    status["items"]?.arrayValue ?? []
  }

  static func item(
    _ status: OracleJson,
    identifier: String,
  ) -> OracleJson? {
    items(status).first { item in
      item["plan_item_id"]?.stringValue == identifier
    }
  }

  /// Drive one item through observation plus a passing verdict under `actor`.
  /// What one actor-driven item leaves behind.
  struct ActorOutcome {
    let recorded: CliBinary.JsonOutcome
    let verifierType: String?
    let status: OracleJson
  }

  static func performUnderActor(
    _ actor: String,
    seed: String,
  ) async throws -> ActorOutcome {
    let directory = try make()
    let runIdentifier = try await startedRunIdentifier(directory, key: "\(seed)-start")
    _ = try await observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "\(seed)-obs",
    )
    let recorded = try await verdict(
      directory,
      run: runIdentifier,
      pass: "item.probe.showcase.thing",
      key: "\(seed)-verdict",
      actor: actor,
    )
    let verdictEvent = try event(directory, run: runIdentifier, ofType: "verdict_recorded")
    return try await ActorOutcome(
      recorded: recorded,
      verifierType: verdictEvent?.at("payload.verifier.type")?.stringValue,
      status: status(directory, run: runIdentifier),
    )
  }

  static func startFromPlan(
    _ directory: TemporaryDirectory,
    key: String,
  ) async throws -> String {
    let planned = try await run(directory, ["plan", "showcase", "--repo", "."])
    #expect(planned.isOk == true, "plan showcase must select both rows")
    let plan = try #require(planned.data["plan"])
    try directory.writeFile("plan.json", contents: plan.encoded)
    let started = try await run(directory, [
      "showcase", "start", "--repo", ".", "--plan-file", "plan.json",
      "--idempotency-key", key,
    ])
    #expect(
      started.isOk == true,
      Comment(rawValue: "start from plan failed: \(started.standardError)"),
    )
    return try #require(started.data["run_id"]?.stringValue)
  }

  static func finishedApprovalRun(
    _ directory: TemporaryDirectory,
    seed: String,
  ) async throws -> String {
    let runIdentifier = try await startedRunIdentifier(directory, key: "\(seed)-start")
    _ = try await observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "\(seed)-obs",
    )
    _ = try await verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "\(seed)-verdict",
    )
    _ = try await finish(directory, run: runIdentifier)
    return runIdentifier
  }
}
