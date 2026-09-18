import Foundation
import Testing

/// The workspace the five planning/cards.yml suites build.
///
/// All five rows are measured through `use-cases plan showcase`,
/// `use-cases plan walkthrough` and `use-cases showcase start` — never by
/// importing the selection code directly.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
enum PlanningWorkspace {
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

  struct RowSpec {
    let name: String
    let value: String
    let journey: String
  }

  /// A row with a REAL verification/approval policy: only these are ever
  /// selectable for a plan.
  static func rowYaml(_ spec: RowSpec) -> String {
    """
      - id: probe.core.\(spec.name)
        title: Row \(spec.name)
        lifecycle: active
        value_tier: \(spec.value)
        journey_role: \(spec.journey)
        usage_frequency: common
        tags: [probe]
        actor: agent
        intent: Exist so a plan has something to select.
        preconditions: [Nothing.]
        trigger: Nothing.
        scenarios:
          - id: probe.core.\(spec.name).golden_runs
            kind: steps
            steps: [Run it.]
            observable_outcomes: [It passes.]
        observable_outcomes: [It exists.]
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
          mode: ask

    """
  }

  /// A spread across value tier and journey role: one critical golden path,
  /// one core edge case, one supporting negative case. A showcase should prefer
  /// the first; a walkthrough should reach all three.
  static let rows = [
    RowSpec(name: "crit_golden", value: "critical", journey: "golden"),
    RowSpec(name: "core_edge", value: "core", journey: "edge"),
    RowSpec(name: "supp_negative", value: "supporting", journey: "negative"),
  ]

  static func make(rows selected: [RowSpec] = rows) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("planning-cards")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: """
      schema_version: 1
      feature:
        id: probe.core
        name: Probe
        summary: Probe.
      use_cases:
      \(selected.map(rowYaml).joined())
      """,
    )
    return directory
  }

  /// Add a second, malformed shard beside the valid one — the matrix degrades
  /// to `partial`, not `unusable`.
  static func addDamagedShard(_ directory: TemporaryDirectory) throws {
    try directory.writeFile(
      "use-cases/broken.yml",
      contents: """
      schema_version: 1
      feature:
        id: probe.broken
      use_cases:
        - id: probe.broken.item
          preconditions: [broken

      """,
    )
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

  static func planShowcase(
    _ directory: TemporaryDirectory,
    _ arguments: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["plan", "showcase", "--repo", "."] + arguments)
  }

  static func planWalkthrough(
    _ directory: TemporaryDirectory,
    _ arguments: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["plan", "walkthrough", "--repo", "."] + arguments)
  }

  static func showcaseStart(
    _ directory: TemporaryDirectory,
    planFile: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["showcase", "start", "--repo", ".", "--plan-file", planFile])
  }

  static func evidenceCounts(_ directory: TemporaryDirectory) async throws -> OracleJson {
    try await run(directory, ["evidence", "status", "--repo", "."]).data["counts"] ?? .null
  }

  static func selectedIdentifiers(_ plan: OracleJson) -> [String] {
    (plan["selected_items"]?.arrayValue ?? []).compactMap { item in
      item["use_case_id"]?.stringValue
    }
  }
}
