import Foundation
import Testing

/// The single-row workspace the lifecycle/signals.yml suites build, and the
/// readers they share — at the scope `lifecycle-signals.test.ts` shares them.
///
/// Everything here talks ONLY to the binary: no core import, no internal call.
/// Each test builds its workspace from scratch, so nothing depends on a fixture
/// that a later change might reshape. UC_RUN_KEY_FILE is always pointed at a
/// throwaway path, so no test reads or writes the developer's own machine key.
enum SignalsWorkspace {
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

  /// A verifier block, indented to sit under `verification_policy.verifiers`.
  static let passingScript = """
          script:
            kind: script
            evidence_kind: test_result
            command: ["/bin/sh", "-c", "exit 0"]
            inputs: ["src/thing.ts"]
  """

  static func featureFile(
    verifier: String,
    requiredKind: String = "test_result",
    verifierId: String = "script",
  ) -> String {
    """
    schema_version: 1
    feature:
      id: probe.core
      name: Probe
      summary: A behaviour that exists so a scenario can be proved through the CLI.
    use_cases:
      - id: probe.core.thing
        title: The thing works
        lifecycle: active
        value_tier: core
        journey_role: golden
        usage_frequency: common
        actor: agent
        intent: Prove one scenario end to end through the binary.
        preconditions: [A source file exists.]
        trigger: An agent runs the loop.
        scenarios:
          - id: probe.core.thing.golden_runs
            kind: steps
            steps: [Run it.]
            observable_outcomes: [It works.]
        observable_outcomes: [The row reaches a proven state.]
        host_applicability:
          - host_surface: codex.cli
            supported: true
        verification_policy:
          mode: requirements
          verifiers:
    \(verifier)
          requirements:
            - evidence_kind: \(requiredKind)
              required_verifiers: [\(verifierId)]
              minimum_count: 1
        approval_policy:
          mode: none

    """
  }

  struct Workspace {
    let directory: TemporaryDirectory
    let environment: [String: String]

    var path: String {
      directory.path
    }

    var runKeyPath: String {
      directory.path + "/machine/run-key"
    }
  }

  /// A bound, ready-to-verify workspace, built only through the CLI.
  static func make(
    verifier: String = passingScript,
    requiredKind: String = "test_result",
    verifierId: String = "script",
    bind: Bool = true,
  ) async throws -> Workspace {
    let directory = try TemporaryDirectory("blackbox")
    try directory.makeDirectory("use-cases")
    try directory.makeDirectory("src")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: featureFile(
        verifier: verifier,
        requiredKind: requiredKind,
        verifierId: verifierId,
      ),
    )
    try directory.writeFile(
      "src/thing.ts",
      contents: "export function thing() {\n  return 1;\n}\n",
    )
    let workspace = Workspace(
      directory: directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )

    if bind {
      let bound = try await run(workspace, [
        "bind", "--repo", ".", "--row", "probe.core.thing", "--file", "src/thing.ts",
        "--mode", "explicit", "--start-line", "1", "--end-line", "3",
      ])
      #expect(bound.isOk == true, Comment(rawValue: "bind failed: \(bound.standardError)"))
    }
    return workspace
  }

  static func run(
    _ workspace: Workspace,
    _ arguments: [String],
    environment: [String: String]? = nil,
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      arguments,
      cwd: workspace.path,
      environment: environment ?? workspace.environment,
    )
  }

  static func runHuman(
    _ workspace: Workspace,
    _ arguments: [String],
  ) async throws -> CliBinary.Outcome {
    try await CliBinary.resolved().run(
      arguments,
      cwd: workspace.path,
      environment: workspace.environment,
    )
  }

  static func scan(
    _ workspace: Workspace,
    environment: [String: String]? = nil,
  ) async throws -> OracleJson {
    try await run(workspace, ["scan", "--repo", "."], environment: environment).data["status"]
      ?? .null
  }

  static func rows(_ status: OracleJson) -> [OracleJson] {
    status["rows"]?.arrayValue ?? []
  }

  static func row(
    _ status: OracleJson,
    identifier: String,
  ) -> OracleJson? {
    rows(status).first { row in
      row["row_id"]?.stringValue == identifier
    }
  }

  static func localStatus(_ status: OracleJson) -> String? {
    rows(status).first?["local_status"]?.stringValue
  }

  static func evidenceCount(
    _ status: OracleJson,
    _ key: String,
  ) -> Int? {
    status.at("acceptance_claim.by_evidence.\(key)")?.intValue
  }

  static func claimable(_ status: OracleJson) -> Bool? {
    status.at("acceptance_claim.claimable")?.boolValue
  }

  /// The unsigned results ledger `use-cases verify` writes by default.
  static let resultsLedger = ".use-cases/verification-results.jsonl"

  static func readOnlyRecord(_ workspace: Workspace) throws -> OracleJson {
    let lines = try workspace.directory.readFile(resultsLedger)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
    #expect(lines.count == 1, "expected exactly one results record")
    return try OracleJson.parse(String(#require(lines.first)))
  }

  static func writeRecord(
    _ workspace: Workspace,
    _ record: OracleJson,
  ) throws {
    try workspace.directory.writeFile(resultsLedger, contents: record.encoded + "\n")
  }

  static func ledgerLineCount(_ workspace: Workspace) throws -> Int {
    try workspace.directory.readFile(resultsLedger)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .filter { line in
        !line.isEmpty
      }
      .count
  }

  /// Bind, verify, and hand back the genuine attested record verify wrote.
  static func verified() async throws -> (workspace: Workspace, record: OracleJson) {
    let workspace = try await make()
    let verified = try await run(workspace, ["verify", "--repo", ".", "--row", "probe.core.thing"])
    #expect(verified.isOk == true, Comment(rawValue: verified.standardOutput))
    return try (workspace, readOnlyRecord(workspace))
  }

  /// Drive the behaviour through the tool, which is what a performed run means.
  static func drive(
    _ workspace: Workspace,
    key: String,
    argv: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await run(workspace, [
      "evidence", "record", "--repo", ".", "--use-case", "probe.core.thing",
      "--perform", "--idempotency-key", key, "--",
    ] + argv)
  }

  static func withField(
    _ record: OracleJson,
    _ changes: [String: OracleJson],
  ) -> OracleJson {
    var fields = record.objectValue ?? [:]
    for (key, value) in changes {
      fields[key] = value
    }
    return .object(fields)
  }

  static func withoutField(
    _ record: OracleJson,
    _ key: String,
  ) -> OracleJson {
    var fields = record.objectValue ?? [:]
    fields.removeValue(forKey: key)
    return .object(fields)
  }
}
