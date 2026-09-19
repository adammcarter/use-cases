import Foundation
import Testing

//: @use-case:lifecycle.signals.variant_fanout#blackbox
/// The black-box oracle for lifecycle/signals.yml, row `variant_fanout`.
struct LifecycleVariantFanoutTests {
  /// The family's matrix, with the verifier command spliced in.
  static func matrix(command: String) -> String {
    """
      schema_version: 1
      feature:
        id: probe.core
        name: Probe
        summary: Probe.
      use_cases:
        - id: probe.core.fam
          title: Variant family
          lifecycle: active
          value_tier: core
          journey_role: golden
          usage_frequency: common
          actor: agent
          intent: Probe variant fan-out.
          preconditions: [A source file exists.]
          trigger: An agent verifies the family.
          scenarios:
            - id: probe.core.fam.golden_runs
              kind: steps
              steps: [Run it.]
              observable_outcomes: [Each variant gets its own record.]
          observable_outcomes: [Each variant gets its own record.]
          host_applicability:
            - host_surface: codex.cli
              supported: true
          verification_policy:
            mode: requirements
            verifiers:
              script:
                kind: script
                evidence_kind: test_result
                command: \(command)
                inputs: ["src/fam.ts"]
            requirements:
              - evidence_kind: test_result
                required_verifiers: [script]
                minimum_count: 1
          approval_policy:
            mode: none
          variants:
            - key: good
              title: A passing variant
            - key: other
              title: Another variant

    """
  }

  /// A family whose verifier passes for every variant except `failing`.
  static func makeFamily(
    token: Bool = true,
    failing: String? = nil,
  ) async throws -> SignalsWorkspace.Workspace {
    let directory = try TemporaryDirectory("blackbox-fam")
    try directory.makeDirectory("use-cases")
    try directory.makeDirectory("src")
    try directory.writeFile("use-cases.yml", contents: SignalsWorkspace.configuration)
    let command = token
      ? "[\"/bin/sh\", \"-c\", \"test {variant} != \(failing ?? "__none__")\"]"
      : "[\"/bin/sh\", \"-c\", \"exit 0\"]"
    try directory.writeFile("use-cases/probe.yml", contents: Self.matrix(command: command))
    try directory.writeFile("src/fam.ts", contents: "export function fam() {\n  return 1;\n}\n")
    let workspace = SignalsWorkspace.Workspace(
      directory: directory,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
    let bound = try await SignalsWorkspace.run(workspace, [
      "bind", "--repo", ".", "--row", "probe.core.fam", "--file", "src/fam.ts",
      "--mode", "explicit", "--start-line", "1", "--end-line", "3",
    ])
    #expect(bound.isOk == true, Comment(rawValue: "bind failed: \(bound.standardError)"))
    return workspace
  }

  static func verify(
    _ workspace: SignalsWorkspace.Workspace,
    extra: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--row", "probe.core.fam"] + extra,
    )
  }

  // golden_loop. One spawn per declared variant, one record each, keyed
  // family::variant, so a reader can see which shape was proved.
  @Test
  func `each variant gets its own ledger record keyed family and variant (variant: spawn)`()
    async throws
  {
    let workspace = try await Self.makeFamily()
    let verified = try await Self.verify(workspace)
    let rows = (verified.data["results"]?.arrayValue ?? []).compactMap { result in
      result["row_id"]?.stringValue
    }.sorted()
    #expect(rows == ["probe.core.fam::good", "probe.core.fam::other"])
  }

  // golden_family_verified_only_when_all_pass.
  @Test
  func `the family is VERIFIED_LOCAL only when every variant passes (variant: verdict)`(
  ) async throws {
    let workspace = try await Self.makeFamily()
    _ = try await Self.verify(workspace)
    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.localStatus(scanned) == "VERIFIED_LOCAL")
  }

  // bad_failing_variant_is_named. A partial failure must be reported as one,
  // and the failing shape named rather than left to be hunted.
  @Test
  func `a failing variant keeps the family out of green, is named, and fails (variant: names)`()
    async throws
  {
    let workspace = try await Self.makeFamily(failing: "other")
    let verified = try await Self.verify(workspace)
    #expect(
      verified.data["exit_code"]?.intValue != 0,
      "a partial failure is not success",
    )

    let scanned = try await SignalsWorkspace.scan(workspace)
    let row = try #require(SignalsWorkspace.rows(scanned).first)
    #expect(row["local_status"]?.stringValue != "VERIFIED_LOCAL")
    #expect(row.encoded.contains("other"), "the failing variant must be named")
  }

  // bad_missing_variant_token_is_a_spec_error. A family whose command cannot
  // distinguish its variants is a spec error, surfaced once — never a false
  // pass.
  @Test
  func `a family with no variant token is a spec error and spawns nothing`()
    async throws
  {
    let workspace = try await Self.makeFamily(token: false)
    let verified = try await Self.verify(workspace)
    #expect(verified.data["exit_code"]?.intValue != 0)
    let codes = (verified.data["errors"]?.arrayValue ?? []).compactMap { error in
      error["code"]?.stringValue
    }
    #expect(codes.contains("VARIANT_TOKEN_MISSING"))
    let missing = codes.filter { code in
      code == "VARIANT_TOKEN_MISSING"
    }
    #expect(missing.count == 1, "surfaced once, not per variant")
    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.localStatus(scanned) != "VERIFIED_LOCAL")
  }

  // edge_dry_run_previews_each_variant, both ways: one entry per variant, and a
  // token-less family previewing as blocked rather than as a run.
  @Test
  func `a dry run previews one entry per variant, and blocked with no token (variant: dry)`()
    async throws
  {
    let fanned = try await Self.verify(Self.makeFamily(), extra: ["--dry-run"])
    let rows = (fanned.data["planned"]?.arrayValue ?? []).compactMap { entry in
      entry["row_id"]?.stringValue
    }.sorted()
    #expect(rows == ["probe.core.fam::good", "probe.core.fam::other"])

    let tokenless = try await Self.makeFamily(token: false)
    let previewed = try await Self.verify(tokenless, extra: ["--dry-run"])
    let allBlocked = (previewed.data["planned"]?.arrayValue ?? []).allSatisfy { entry in
      entry["disposition"]?.stringValue == "blocked"
    }
    #expect(allBlocked)
  }
}

//: @use-case:end lifecycle.signals.variant_fanout#blackbox
