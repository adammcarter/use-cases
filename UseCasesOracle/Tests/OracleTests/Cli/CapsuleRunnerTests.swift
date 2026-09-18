import Foundation
import Testing

/// The black-box oracle for capsule/runner.yml.
///
/// This is the one place a demo capsule stops being prepared material and
/// becomes a live, script-led showcase run: `capsule run --execute-commands`
/// starts a real showcase run, executes command steps for real, and records
/// every step into the showcase ledger. `CapsuleDemosTests` covers the planning
/// and safety boundary; this file covers what happens once a capsule is
/// actually performed.
///
/// Self-contained on purpose: a shared oracle file means one edit stales every
/// row bound to it.
struct CapsuleRunnerTests {
  static let workspaceConfiguration = """
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

  /// A single command-backed row, approval_policy mode: none, so a passing run
  /// never has a reason to require sign-off.
  static let matrixCommandOnly = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.cmd
      title: Command row
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so a capsule can run a command against it.
      preconditions: [Nothing.]
      trigger: A capsule runs a command.
      scenarios:
        - id: probe.core.cmd.golden_runs
          kind: steps
          steps: [Run the command.]
          observable_outcomes: [The command succeeds.]
      observable_outcomes: [It exists.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  /// A second row with an observation-only item, so its plan item can never
  /// receive a verdict without someone actually recording an observation.
  static let matrixCommandAndObservation = matrixCommandOnly + """
    - id: probe.core.obs
      title: Observation row
      lifecycle: active
      value_tier: core
      journey_role: alternate
      usage_frequency: common
      actor: agent
      intent: Exist so a capsule can leave a pending observation.
      preconditions: [Nothing.]
      trigger: A capsule asks for an observation.
      scenarios:
        - id: probe.core.obs.golden_runs
          kind: steps
          steps: [Observe it.]
          observable_outcomes: [It was seen.]
      observable_outcomes: [It exists.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  static let capsuleCommandOnly = """
  schema_version: 1
  capsule_id: capsule.probe.scripted
  title: Probe scripted
  mode: showcase
  description: Probe scripted capsule.
  audience: reviewer
  timebox_seconds: 600
  items:
    - use_case_id: probe.core.cmd
      scenario_ids: [probe.core.cmd.golden_runs]
      runbook:
        - kind: command
          executable: node
          argv: ["-e", "console.log('hi')"]
          working_directory: "."
          expected_exit_codes: [0]
  permissions:
    command_execution: true

  """

  static let capsuleCommandAndObservation = """
  schema_version: 1
  capsule_id: capsule.probe.scripted
  title: Probe scripted with a pending observation
  mode: showcase
  description: Probe scripted capsule with one command item and one observation-only item.
  audience: reviewer
  timebox_seconds: 600
  items:
    - use_case_id: probe.core.cmd
      scenario_ids: [probe.core.cmd.golden_runs]
      runbook:
        - kind: command
          executable: node
          argv: ["-e", "console.log('hi')"]
          working_directory: "."
          expected_exit_codes: [0]
    - use_case_id: probe.core.obs
      scenario_ids: [probe.core.obs.golden_runs]
      runbook:
        - kind: observation
          text: Confirm you saw it.
  permissions:
    command_execution: true

  """

  static func makeWorkspace(
    matrix: String,
    capsule: String,
  ) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("capsule-runner")
    try directory.makeDirectory("use-cases")
    try directory.makeDirectory("demo-capsules")
    try directory.writeFile("use-cases.yml", contents: workspaceConfiguration)
    try directory.writeFile("use-cases/probe.yml", contents: matrix)
    try directory.writeFile("demo-capsules/probe.yml", contents: capsule)
    return directory
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      [arguments[0], arguments[1], "--repo", "."] + arguments.dropFirst(2),
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  /// The event types recorded in a run's own showcase-runs ledger, in order.
  static func ledgerEventTypes(
    _ directory: TemporaryDirectory,
    runIdentifier: String,
  ) throws -> [String] {
    try directory.readFile("showcase-runs/\(runIdentifier)/events.jsonl")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .compactMap { line in
        try? OracleJson.parse(String(line))["event_type"]?.stringValue
      }
  }

  // golden_cli. Running the capsule with --execute-commands and a stable
  // idempotency key performs a real showcase run: it starts the run from the
  // capsule's plan, executes the command for real, and records the whole
  // sequence — start, the command action, its observation, its verdict, and
  // the finish — as the showcase ledger's own events, in order.
  @Test
  func `a command-backed capsule records a full run_started to run_finished ledger`()
    async throws
  {
    let directory = try Self.makeWorkspace(
      matrix: Self.matrixCommandOnly,
      capsule: Self.capsuleCommandOnly,
    )

    let performed = try await Self.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.scripted",
      "--execute-commands", "--idempotency-key", "runner-golden",
    ])

    #expect(performed.isOk == true, Comment(rawValue: performed.standardOutput))
    #expect(performed.data["complete"]?.boolValue == true)
    #expect(performed.data.at("status.execution_status")?.stringValue == "completed")
    #expect(performed.data.at("status.run_outcome")?.stringValue == "passed")
    let runIdentifier = try #require(performed.data["run_id"]?.stringValue)
    #expect(
      try Self.ledgerEventTypes(directory, runIdentifier: runIdentifier) == [
        "run_started",
        "action_recorded",
        "observation_recorded",
        "verdict_recorded",
        "run_finished",
      ],
    )
  }

  // bad_pending_observations_block_the_finish. A second item needs a runtime
  // observation that nothing in this run ever supplies. `capsule run` itself
  // must not silently call the run finished and passed — and even an explicit
  // `showcase finish` must not report it as passed while that observation is
  // still outstanding.
  @Test
  func `a run with an unresolved observation never reports passed`() async throws {
    let directory = try Self.makeWorkspace(
      matrix: Self.matrixCommandAndObservation,
      capsule: Self.capsuleCommandAndObservation,
    )

    let performed = try await Self.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.scripted",
      "--execute-commands", "--idempotency-key", "runner-pending",
    ])

    #expect(
      performed.data["complete"]?.boolValue == false,
      "the run cannot be complete while an observation is outstanding",
    )
    let pending = (performed.data["pending_steps"]?.arrayValue ?? []).contains { step in
      step["use_case_id"]?.stringValue == "probe.core.obs"
        && step["reason"]?.stringValue == "runtime_observation_required"
    }
    #expect(pending)
    #expect(
      performed.data.at("status.execution_status")?.stringValue != "completed",
      "capsule run does not auto-finish a run with pending steps",
    )

    let runIdentifier = try #require(performed.data["run_id"]?.stringValue)
    let finished = try await Self.run(directory, ["showcase", "finish", "--run", runIdentifier])
    #expect(
      finished.data.at("status.run_outcome")?.stringValue != "passed",
      "finishing early never manufactures a passed outcome",
    )
  }

  // edge_no_user_approval_unless_the_row_requires_it. The selected row's
  // approval_policy is mode: none, so a passing scripted run must reach
  // approval_state "not_required" on its own — nothing in this test ever
  // calls `showcase approve`.
  @Test
  func `a passing run never records approval for a row that does not require it`()
    async throws
  {
    let directory = try Self.makeWorkspace(
      matrix: Self.matrixCommandOnly,
      capsule: Self.capsuleCommandOnly,
    )

    let performed = try await Self.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.scripted",
      "--execute-commands", "--idempotency-key", "runner-approval",
    ])

    #expect(performed.data.at("status.run_outcome")?.stringValue == "passed")
    #expect(performed.data.at("status.approval_state")?.stringValue == "not_required")
  }
}
