import Foundation
import Testing

/// The black-box oracle for evidence/core.yml.
///
/// One row, and until now its whole scenario body was a single line: "Run
/// evidence record." What the row actually promises is narrower and more
/// interesting — proof is persisted as append-only history and NOTHING else is
/// created alongside it, because a summary file would become a second source of
/// truth that nobody replays.
///
/// Self-contained: a shared oracle fixture means one edit stales every row
/// bound to it, so the workspace is built here rather than borrowed.
struct EvidenceCoreTests {
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
      intent: Exist so evidence can be recorded against it.
      preconditions: [Nothing.]
      trigger: An agent records evidence.
      scenarios:
        - id: probe.core.alpha.golden_runs
          kind: steps
          steps: [Record it.]
          observable_outcomes: [An event is appended.]
      observable_outcomes: [A JSONL event is appended under evidence.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  struct Workspace {
    let directory: TemporaryDirectory
    let environment: [String: String]
  }

  static func makeWorkspace() throws -> Workspace {
    let directory = try TemporaryDirectory("evidence-core")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: workspaceConfiguration)
    try directory.writeFile("use-cases/probe.yml", contents: matrix)
    return Workspace(
      directory: directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func record(
    _ workspace: Workspace,
    useCase: String,
    key: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      [
        "evidence", "record", "--repo", ".", "--use-case", useCase,
        "--summary", "the behaviour was observed", "--idempotency-key", key,
      ],
      cwd: workspace.directory.path,
      environment: workspace.environment,
    )
  }

  // golden_cli.
  @Test
  func `recording evidence appends one JSONL event under evidence`() async throws {
    let workspace = try Self.makeWorkspace()
    let recorded = try await Self.record(workspace, useCase: "probe.core.alpha", key: "first")

    #expect(recorded.isOk == true, Comment(rawValue: recorded.standardOutput))
    #expect(recorded.data["appended"]?.boolValue == true)
    let ledgerPath = try #require(recorded.data["ledger_path"]?.stringValue)
    #expect(ledgerPath.hasPrefix("evidence/"))
    #expect(ledgerPath.hasSuffix(".jsonl"))

    let stored = try workspace.directory.readFile(ledgerPath)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(stored.split(separator: "\n").count == 1, "one event, one line")
    let event = try OracleJson.parse(stored)
    #expect(event["event_type"]?.stringValue == "evidence_recorded")
  }

  // bad_unresolvable_use_case. A dangling target is refused rather than
  // recorded and left for someone to trip over later.
  @Test
  func `evidence naming a use case that does not resolve appends nothing`() async throws {
    let workspace = try Self.makeWorkspace()
    _ = try await Self.record(workspace, useCase: "probe.core.alpha", key: "first")
    let before = workspace.directory.files(under: "evidence")

    let refused = try await Self.record(workspace, useCase: "probe.core.ghost", key: "ghost")
    #expect(refused.isOk == false)
    #expect(refused.envelope.diagnostics.encoded.contains("evidence.use_case.unresolved"))
    #expect(
      workspace.directory.files(under: "evidence") == before,
      "a refused record writes nothing",
    )
  }

  // edge_no_summary_state_is_created. The events ARE the state. A summary or
  // index file beside them would be a second source of truth that no replay
  // reads, and it would drift the moment anything was corrected.
  @Test
  func `recording creates no summary beside the append-only history`() async throws {
    let workspace = try Self.makeWorkspace()
    _ = try await Self.record(workspace, useCase: "probe.core.alpha", key: "first")
    _ = try await Self.record(workspace, useCase: "probe.core.alpha", key: "second")

    let files = workspace.directory.files(under: "evidence")
    #expect(!files.isEmpty)
    let other = files.filter { file in
      !file.hasSuffix(".jsonl")
    }
    #expect(
      other.isEmpty,
      Comment(
        rawValue: "only append-only ledgers may exist, found: \(other.joined(separator: ", "))",
      ),
    )
  }
}
