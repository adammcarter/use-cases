import Foundation
import Testing

/// The multi-row fixture for lifecycle/signals.yml.
///
/// The single-row suites need only one behaviour; these rows are about how rows
/// affect EACH OTHER — one row's verify preserving another's evidence, one
/// unbound row blocking the whole claim — so they need a workspace with
/// several.
enum SignalsMultiRow {
  struct Options {
    /// Rows to create. Every one gets a source file and a passing verifier.
    let rows: [String]
    /// Rows to bind. Anything omitted stays deliberately UNBOUND.
    var bind: [String]?
    /// Give this row a verifier that cannot resolve, for the blocked-plan case.
    var unresolvable: String?

    init(
      rows: [String],
      bind: [String]? = nil,
      unresolvable: String? = nil,
    ) {
      self.rows = rows
      self.bind = bind
      self.unresolvable = unresolvable
    }
  }

  /// A plan reports `blocked` when NO verifier resolves. A missing executable
  /// is not that case — the plan never stats the binary, so it still says
  /// "run" — and nor is an unknown preset, which the schema refuses outright.
  /// Requiring a verifier the policy never defines is the real shape, and it is
  /// the same defect 22 rows in this repo's own matrix carry.
  static func verifierBlock(
    row name: String,
    unresolvable: Bool,
  ) -> String {
    """
            \(unresolvable ? "other" : "script"):
              kind: script
              evidence_kind: test_result
              command: ["/bin/sh", "-c", "exit 0"]
              inputs: ["src/\(name).ts"]
    """
  }

  static func rowYaml(
    _ name: String,
    unresolvable: Bool,
  ) -> String {
    """
      - id: probe.core.\(name)
        title: Row \(name)
        lifecycle: active
        value_tier: core
        journey_role: golden
        usage_frequency: common
        actor: agent
        intent: Probe row \(name).
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
    \(verifierBlock(row: name, unresolvable: unresolvable))
          requirements:
            - evidence_kind: test_result
              required_verifiers: [script]
              minimum_count: 1
        approval_policy:
          mode: none

    """
  }

  static func make(_ options: Options) async throws -> SignalsWorkspace.Workspace {
    let directory = try TemporaryDirectory("blackbox-multi")
    try directory.makeDirectory("use-cases")
    try directory.makeDirectory("src")
    try directory.writeFile("use-cases.yml", contents: SignalsWorkspace.configuration)
    let body = options.rows.map { name in
      rowYaml(name, unresolvable: options.unresolvable == name)
    }.joined()
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: """
      schema_version: 1
      feature:
        id: probe.core
        name: Probe
        summary: Probe.
      use_cases:
      \(body)
      """,
    )
    for name in options.rows {
      // Lines 1-3 are the bound span. The helper below it exists so a test can
      // edit the file WITHOUT hitting the span — which is the whole distinction
      // impact_leads_with_the_union turns on.
      try directory.writeFile(
        "src/\(name).ts",
        contents: """
        export function \(name)() {
          return 1;
        }

        export function \(name)Helper() {
          return 2;
        }

        """,
      )
    }

    let workspace = SignalsWorkspace.Workspace(
      directory: directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
    for name in options.bind ?? options.rows {
      let bound = try await SignalsWorkspace.run(workspace, [
        "bind", "--repo", ".", "--row", "probe.core.\(name)", "--file", "src/\(name).ts",
        "--mode", "explicit", "--start-line", "1", "--end-line", "3",
      ])
      #expect(
        bound.isOk == true,
        Comment(rawValue: "bind \(name) failed: \(bound.standardError)"),
      )
    }
    return workspace
  }

  static func verifyAll(
    _ workspace: SignalsWorkspace.Workspace,
  ) async throws -> CliBinary.JsonOutcome {
    try await SignalsWorkspace.run(workspace, ["verify", "--repo", ".", "--all"])
  }

  static func verifyRow(
    _ workspace: SignalsWorkspace.Workspace,
    _ row: String,
  ) async throws -> CliBinary.JsonOutcome {
    try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--row", "probe.core.\(row)"],
    )
  }

  static func rowStatus(
    _ workspace: SignalsWorkspace.Workspace,
    _ row: String,
  ) async throws -> OracleJson? {
    try await SignalsWorkspace.row(
      SignalsWorkspace.scan(workspace),
      identifier: "probe.core.\(row)",
    )
  }

  /// A bare git repo with no workspace, for the commands that create one.
  static func makeBareRepo(
    gitignore: String? = nil,
  ) async throws -> SignalsWorkspace.Workspace {
    let directory = try TemporaryDirectory("blackbox-bare")
    let workspace = SignalsWorkspace.Workspace(
      directory: directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
    _ = try await SignalsWorkspace.runHuman(workspace, ["--version"])
    try await git(directory, ["init", "-q", "."])
    try await git(directory, ["config", "user.email", "probe@example.com"])
    try await git(directory, ["config", "user.name", "Probe"])
    if let gitignore {
      try directory.writeFile(".gitignore", contents: gitignore)
    }
    return workspace
  }

  static func git(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws {
    let outcome = try await OracleProcess.run(
      executable: "/usr/bin/git",
      arguments: arguments,
      cwd: directory.path,
      environment: [:],
    )
    #expect(
      outcome.exitCode == 0,
      Comment(
        rawValue: "git \(arguments.joined(separator: " ")) failed: \(outcome.standardError)",
      ),
    )
  }
}
