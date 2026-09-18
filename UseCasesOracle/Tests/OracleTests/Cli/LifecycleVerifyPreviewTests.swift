import Foundation
import Testing

//: @use-case:lifecycle.signals.verify_can_be_previewed#blackbox
/// The black-box oracle for lifecycle/signals.yml, row
/// `verify_can_be_previewed`.
struct LifecycleVerifyPreviewTests {
  static func planned(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data["planned"]?.arrayValue ?? []
  }

  // golden_dry_run. The plan names each targeted row and the exact command.
  @Test
  func `the plan names each targeted row and the command that would run`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    let previewed = try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--all", "--dry-run"],
    )

    #expect(previewed.data["dry_run"]?.boolValue == true)
    let rows = Self.planned(previewed).compactMap { entry in
      entry["row_id"]?.stringValue
    }.sorted()
    #expect(rows == ["probe.core.alpha", "probe.core.beta"])
    let first = try #require(Self.planned(previewed).first)
    let command = (first["command"]?.arrayValue ?? []).compactMap { part in
      part.stringValue
    }
    #expect(command == ["/bin/sh", "-c", "exit 0"])
    #expect(first["disposition"]?.stringValue == "run")
  }

  // bad_unresolvable_verifier_is_blocked. A row the plan cannot run must be
  // reported as blocked, not quietly dropped — a plan that omits a row
  // under-reports the very cost it was asked for.
  @Test
  func `a row whose verifier cannot be resolved is reported as blocked`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(
      .init(rows: ["alpha", "beta"], unresolvable: "beta"),
    )
    let previewed = try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--all", "--dry-run"],
    )

    let beta = Self.planned(previewed).first { entry in
      entry["row_id"]?.stringValue == "probe.core.beta"
    }
    #expect(beta != nil, "the unresolvable row must still appear in the plan")
    #expect(beta?["disposition"]?.stringValue != "run")
  }

  // edge_nothing_is_executed_or_written. A plan is never evidence.
  @Test
  func `a dry run executes nothing, writes no ledger and mints no record`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha", "beta"]))
    let previewed = try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--all", "--dry-run"],
    )

    let results = previewed.data["results"]?.arrayValue ?? []
    #expect(results.isEmpty)
    #expect(previewed.data["out_path"]?.isNull == true)
    #expect(
      !workspace.directory.exists(SignalsWorkspace.resultsLedger),
      "a plan must write no results ledger",
    )
    let alpha = try await SignalsMultiRow.rowStatus(workspace, "alpha")
    #expect(alpha?["local_status"]?.stringValue != "VERIFIED_LOCAL")
  }
}

//: @use-case:end lifecycle.signals.verify_can_be_previewed#blackbox

//: @use-case:lifecycle.signals.bind_names_the_next_step#blackbox
/// The black-box oracle for lifecycle/signals.yml, row
/// `bind_names_the_next_step`.
struct LifecycleBindNextStepTests {
  // golden_after_bind. Rows were being bound and then abandoned; a successful
  // bind ends with the command that actually proves the behaviour.
  @Test
  func `a successful bind hands back the verify command for that row`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"], bind: []))
    let bound = try await SignalsWorkspace.run(workspace, [
      "bind", "--repo", ".", "--row", "probe.core.alpha", "--file", "src/alpha.ts",
      "--mode", "explicit", "--start-line", "1", "--end-line", "3",
    ])

    #expect(bound.isOk == true)
    #expect(
      bound.data["next_command"]?.stringValue == "use-cases verify --row probe.core.alpha",
    )
  }

  // edge_bind_alone_is_not_proof. Binding says where the behaviour lives; it
  // says nothing about whether it works.
  @Test
  func `binding alone never moves a row to a proven state`() async throws {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    let row = try await SignalsMultiRow.rowStatus(workspace, "alpha")
    #expect(row?["status"]?.stringValue == "UNPROVEN")
    #expect(row?["local_status"]?.stringValue == "UNVERIFIED_LOCAL")
    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.claimable(scanned) == false)
  }
}

//: @use-case:end lifecycle.signals.bind_names_the_next_step#blackbox
