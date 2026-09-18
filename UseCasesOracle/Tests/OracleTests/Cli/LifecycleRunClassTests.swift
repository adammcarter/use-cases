import Foundation
import Testing

//: @use-case:lifecycle.signals.run_class_is_derived#blackbox
/// The black-box oracle for lifecycle/signals.yml, row `run_class_is_derived`.
struct LifecycleRunClassTests {
  /// A preset verifier carries NO `kind:` — the preset IS the kind, and adding
  /// one makes the row invalid. Measured against the schema, not assumed.
  static let overclaimingSuite = """
          suite:
            preset: python.pytest
            evidence_kind: live_demo
  """

  static let honestMakeTarget = """
          suite:
            preset: make.target
            evidence_kind: live_demo
  """

  /// bad_overclaimed_live_demo. A named test runner is a unit suite by
  /// definition, so a row calling one a live demo is overclaiming in a way the
  /// tool can prove — and it must say so without rewriting the author's YAML.
  static let honestSuite = """
          suite:
            preset: python.pytest
            evidence_kind: test_result
  """

  static func verify(
    _ workspace: SignalsWorkspace.Workspace,
  ) async throws -> CliBinary.JsonOutcome {
    try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--row", "probe.core.thing"],
    )
  }

  static func firstResult(_ outcome: CliBinary.JsonOutcome) throws -> OracleJson {
    try #require(
      outcome.data["results"]?.arrayValue?.first,
      Comment(rawValue: outcome.standardOutput),
    )
  }

  // golden_suite_preset. A named test runner IS a unit suite, by definition.
  @Test
  func `a test-runner preset records run_class suite`() async throws {
    let workspace = try await SignalsWorkspace.make(
      verifier: Self.honestSuite,
      requiredKind: "test_result",
      verifierId: "suite",
    )
    let verified = try await Self.verify(workspace)
    #expect(try Self.firstResult(verified)["run_class"]?.stringValue == "suite")
  }

  // golden_arbitrary_script_is_a_command. Anything else is a command, and
  // verify never mints a journey — spawning a process is not a demonstration.
  @Test
  func `an arbitrary script records run_class command, never suite or journey`()
    async throws
  {
    let workspace = try await SignalsWorkspace.make()
    let verified = try await Self.verify(workspace)
    let runClass = try Self.firstResult(verified)["run_class"]?.stringValue
    #expect(runClass == "command")
    #expect(runClass != "journey")
  }

  // edge_declared_evidence_kind_is_preserved. Overclaim is recorded as a flag
  // BESIDE the claim; the ledger corrects nobody's YAML.
  @Test
  func `the declared evidence_kind is preserved alongside the overclaim flag`()
    async throws
  {
    let workspace = try await SignalsWorkspace.make(
      verifier: Self.overclaimingSuite,
      requiredKind: "live_demo",
      verifierId: "suite",
    )
    let record = try await Self.firstResult(Self.verify(workspace))
    #expect(record["evidence_kind"]?.stringValue == "live_demo")
    #expect(record["evidence_kind_overclaimed"]?.boolValue == true)
  }

  @Test
  func `a test-runner preset declaring live_demo is recorded as overclaimed`()
    async throws
  {
    let workspace = try await SignalsWorkspace.make(
      verifier: Self.overclaimingSuite,
      requiredKind: "live_demo",
      verifierId: "suite",
    )
    let verified = try await Self.verify(workspace)
    let record = try Self.firstResult(verified)

    #expect(
      record["run_class"]?.stringValue == "suite",
      "a test-runner preset must record run_class suite",
    )
    #expect(record["evidence_kind_overclaimed"]?.boolValue == true)
    #expect(
      record["evidence_kind"]?.stringValue == "live_demo",
      "the ledger must not rewrite the author's YAML",
    )
    let overclaimed = (verified.data["overclaimed_rows"]?.arrayValue ?? []).compactMap { row in
      row.stringValue
    }
    #expect(overclaimed.contains("probe.core.thing"))
  }

  // edge_script_live_demo_is_left_alone, the control: a make target may
  // genuinely drive the product, so the tool cannot call it a lie.
  @Test
  func `a make target declaring live_demo is left alone`() async throws {
    let workspace = try await SignalsWorkspace.make(
      verifier: Self.honestMakeTarget,
      requiredKind: "live_demo",
      verifierId: "suite",
    )
    let verified = try await Self.verify(workspace)
    let record = try Self.firstResult(verified)

    #expect(record["run_class"]?.stringValue == "command")
    #expect(record["evidence_kind_overclaimed"]?.boolValue == false)
    let overclaimed = (verified.data["overclaimed_rows"]?.arrayValue ?? []).compactMap { row in
      row.stringValue
    }
    #expect(!overclaimed.contains("probe.core.thing"))
  }
}

//: @use-case:end lifecycle.signals.run_class_is_derived#blackbox
