import Foundation
import Testing

/// The workspace the three lifecycle/bindings.yml suites build.
///
/// Deliberately self-contained rather than sharing the signals fixtures. Every
/// row declares its oracle file as a verifier input, so a shared file means one
/// edit stales every row bound to it — measured on the signals file, where
/// renaming five tests dropped all twelve rows to STALE_LOCAL at once. One file
/// per feature area keeps that blast radius to the area being worked on.
///
/// Everything here talks only to the binary. Each test builds its workspace
/// from scratch and points UC_RUN_KEY_FILE at a throwaway path, so no test
/// reads or writes the developer's own machine key.
enum BindingsWorkspace {
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

  static func rowYaml(_ name: String) -> String {
    """
      - id: probe.core.\(name)
        title: Row \(name)
        lifecycle: active
        value_tier: core
        journey_role: golden
        usage_frequency: common
        actor: agent
        intent: Probe \(name).
        preconditions: [A source file exists.]
        trigger: An agent verifies.
        scenarios:
          - id: probe.core.\(name).golden_runs
            kind: steps
            steps: [Run it.]
            observable_outcomes: [It passes.]
        observable_outcomes: [The row reaches VERIFIED_LOCAL.]
        host_applicability:
          - host_surface: codex.cli
            supported: true
        verification_policy:
          mode: requirements
          verifiers:
            script:
              kind: script
              evidence_kind: test_result
              command: ["/bin/sh", "-c", "exit 0"]
              inputs: ["src/\(name).ts"]
          requirements:
            - evidence_kind: test_result
              required_verifiers: [script]
              minimum_count: 1
        approval_policy:
          mode: none

    """
  }

  /// A workspace with the named rows, nothing bound yet. Each source file holds
  /// three well-separated declarations so two suffixed spans both fit — a span
  /// past end-of-file fails with BIND_SPAN_OUT_OF_RANGE rather than doing
  /// anything interesting.
  static func make(rows: [String]) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("bindings")
    try directory.makeDirectory("use-cases")
    try directory.makeDirectory("src")
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
      \(rows.map(rowYaml).joined())
      """,
    )
    for name in rows {
      try directory.writeFile(
        "src/\(name).ts",
        contents: """
        export function \(name)One() {
          return 1;
        }

        export function \(name)Two() {
          return 2;
        }

        export function \(name)Three() {
          return 3;
        }

        """,
      )
    }
    return directory
  }

  /// Run a use-cases subcommand against this workspace, with --repo wired in.
  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      [arguments[0], "--repo", "."] + arguments.dropFirst(),
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func bind(
    _ directory: TemporaryDirectory,
    row: String,
    file: String,
    start: Int,
    end: Int,
    suffix: String? = nil,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "bind", "--row", "probe.core.\(row)", "--file", file,
      "--mode", "explicit", "--start-line", String(start), "--end-line", String(end),
    ] + (suffix.map { value in ["--suffix", value] } ?? []))
  }

  static func rebind(
    _ directory: TemporaryDirectory,
    row: String,
    file: String,
    start: Int,
    end: Int,
    suffix: String? = nil,
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, [
      "rebind", "--row", "probe.core.\(row)", "--file", file,
      "--mode", "explicit", "--start-line", String(start), "--end-line", String(end),
    ] + (suffix.map { value in ["--suffix", value] } ?? []))
  }

  static func unbind(
    _ directory: TemporaryDirectory,
    row: String,
    extra: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await run(
      directory,
      ["unbind", "--row", "probe.core.\(row)", "--reason", "row_retired"] + extra,
    )
  }

  static func scan(_ directory: TemporaryDirectory) async throws -> OracleJson {
    try await run(directory, ["scan"]).data
  }

  static func scannedRow(
    _ directory: TemporaryDirectory,
    row: String,
  ) async throws -> OracleJson? {
    let scanned = try await scan(directory)
    return (scanned.at("status.rows")?.arrayValue ?? []).first { entry in
      entry["row_id"]?.stringValue == "probe.core.\(row)"
    }
  }

  static func integrityCodes(_ scanned: OracleJson) -> [String] {
    (scanned.at("status.integrity_errors")?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
  }

  static func markerLines(
    _ directory: TemporaryDirectory,
    file: String,
  ) throws -> [String] {
    try directory.readFile(file)
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .filter { line in
        line.contains("@use-case:")
      }
  }

  static func errorCodes(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["errors"]?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
  }

  static func registryLineCount(_ directory: TemporaryDirectory) throws -> Int {
    try directory.readFile(".use-cases/bindings.jsonl")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .filter { line in
        !line.isEmpty
      }
      .count
  }

  static func deleteRow(
    _ directory: TemporaryDirectory,
    row: String,
  ) throws {
    let text = try directory.readFile("use-cases/probe.yml")
    guard let start = text.range(of: "  - id: probe.core.\(row)") else {
      return
    }
    let rest = text[start.upperBound...]
    let next = rest.range(of: "  - id: probe.core.")
    let head = String(text[text.startIndex ..< start.lowerBound])
    let tail = next.map { range in
      String(rest[range.lowerBound...])
    } ?? ""
    try directory.writeFile("use-cases/probe.yml", contents: head + tail)
  }
}
