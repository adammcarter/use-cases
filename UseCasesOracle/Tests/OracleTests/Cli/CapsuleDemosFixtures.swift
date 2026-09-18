import Foundation
import Testing

/// The workspace and capsules the five capsule/demos.yml suites build.
///
/// A demo capsule is prepared material: a YAML file that names use-case and
/// scenario ids and a runbook to perform them with. The five rows draw one line,
/// over and over, in different ways: a capsule is never itself proof. Planning
/// it, validating it, even inspecting it never records an event — only a live
/// run (capsule.live_runner, covered in `CapsuleRunnerTests`) does that.
///
/// Self-contained on purpose: a shared oracle file means one edit stales every
/// row bound to it.
enum CapsuleDemosWorkspace {
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

  /// One active row a capsule can reference. Reused verbatim (or lightly
  /// edited) by most scenarios below.
  static let matrixAlpha = """
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
      intent: Exist so a capsule can reference it.
      preconditions: [Nothing.]
      trigger: A capsule references it.
      scenarios:
        - id: probe.core.alpha.golden_runs
          kind: steps
          steps: [Do it.]
          observable_outcomes: [It works.]
      observable_outcomes: [It exists.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  /// The instruction/observation capsule three suites share.
  static let smokeCapsule = """
  schema_version: 1
  capsule_id: capsule.probe.smoke
  title: Probe smoke
  mode: showcase
  description: Probe smoke capsule.
  audience: reviewer
  timebox_seconds: 600
  items:
    - use_case_id: probe.core.alpha
      scenario_ids: [probe.core.alpha.golden_runs]
      runbook:
        - kind: instruction
          text: Do the thing.
        - kind: observation
          text: Confirm it worked.
  permissions:
    command_execution: false

  """

  static func make(matrix: String = matrixAlpha) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("capsule-demos")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile("use-cases/probe.yml", contents: matrix)
    return directory
  }

  static func writeCapsule(
    _ directory: TemporaryDirectory,
    contents: String,
    filename: String = "probe.yml",
  ) throws {
    try directory.writeFile("demo-capsules/\(filename)", contents: contents)
  }

  /// A capsule whose single runbook step is a command.
  static func commandCapsule(
    executable: String,
    argv: [String],
    workingDirectory: String,
    expectedExitCodes: [Int],
    permitted: Bool,
  ) -> String {
    let arguments = OracleJson.array(argv.map(OracleJson.string)).encoded
    let codes = OracleJson.array(expectedExitCodes.map { code in
      OracleJson.number(Double(code))
    }).encoded
    return """
    schema_version: 1
    capsule_id: capsule.probe.cmd
    title: Probe command
    mode: showcase
    description: Probe command capsule.
    audience: reviewer
    timebox_seconds: 600
    items:
      - use_case_id: probe.core.alpha
        scenario_ids: [probe.core.alpha.golden_runs]
        runbook:
          - kind: command
            executable: "\(executable)"
            argv: \(arguments)
            working_directory: "\(workingDirectory)"
            expected_exit_codes: \(codes)
    permissions:
      command_execution: \(permitted)

    """
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
    extraEnvironment: [String: String] = [:],
  ) async throws -> CliBinary.JsonOutcome {
    var environment = ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"]
    for (key, value) in extraEnvironment {
      environment[key] = value
    }
    return try await CliBinary.resolved().runJson(
      [arguments[0], arguments[1], "--repo", "."] + arguments.dropFirst(2),
      cwd: directory.path,
      environment: environment,
    )
  }

  static func planItems(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data.at("plan_result.plan.selected_items")?.arrayValue ?? []
  }
}
