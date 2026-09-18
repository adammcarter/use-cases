import Foundation
import Testing

//: @use-case:capsule.demos.persisted_smoke_runbook#blackbox
/// The black-box oracle for capsule/demos.yml, row `persisted_smoke_runbook`.
struct CapsulePersistedRunbookTests {
  // golden_plan. Validate the capsule file, then generate a plan from it, and
  // confirm the referenced use-case and scenario ids actually resolve against
  // the matrix rather than just being strings sitting in a YAML file.
  @Test
  func `a persisted capsule validates and plans, resolving its referenced ids`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )

    let validated = try await CapsuleDemosWorkspace.run(directory, ["capsule", "validate"])
    #expect(validated.isOk == true, Comment(rawValue: validated.standardOutput))
    #expect(validated.data["complete"]?.boolValue == true)

    let planned = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    #expect(planned.isOk == true)
    #expect(planned.data.at("plan_result.outcome")?.stringValue == "generated")
    let item = try #require(CapsuleDemosWorkspace.planItems(planned).first)
    #expect(item["use_case_id"]?.stringValue == "probe.core.alpha")
    let scenarios = (item["scenario_ids"]?.arrayValue ?? []).compactMap { entry in
      entry.stringValue
    }
    #expect(scenarios == ["probe.core.alpha.golden_runs"])
  }

  // bad_a_capsule_is_not_proof. Validating and planning a capsule reads and
  // reasons about it, but records nothing. `matrix status` is the CLI's own
  // composed view of proof, so if a capsule counted as evidence it would show
  // up there.
  @Test
  func `validating and planning a capsule records no evidence`() async throws {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )

    _ = try await CapsuleDemosWorkspace.run(directory, ["capsule", "validate"])
    _ = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )

    let statused = try await CapsuleDemosWorkspace.run(directory, ["matrix", "status"])
    let ledgers = statused.data.at("evidence.ledgers")?.arrayValue ?? []
    #expect(ledgers.isEmpty, "no showcase or evidence ledger was ever written")
    #expect(statused.data.at("evidence.counts.aggregates_active")?.intValue == 0)
  }

  // edge_the_same_capsule_serves_repeated_demos. Planning is a pure read: the
  // same capsule against an unchanged matrix produces the identical plan, so
  // an agent never has to reselect rows by hand for a repeat demo.
  @Test
  func `planning the same capsule twice without changes produces an identical plan`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )

    let first = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    let second = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )

    let firstPlan = first.data.at("plan_result.plan")
    let secondPlan = second.data.at("plan_result.plan")
    #expect(
      secondPlan?["plan_content_hash"] == firstPlan?["plan_content_hash"],
    )
    #expect(secondPlan == firstPlan)
  }
}

//: @use-case:end capsule.demos.persisted_smoke_runbook#blackbox

//: @use-case:capsule.demos.adhoc_release_demo#blackbox
/// The black-box oracle for capsule/demos.yml, row `adhoc_release_demo`.
struct CapsuleAdhocDemoTests {
  // golden_start. An ad hoc demo has no capsule file at all: the selection is
  // made on the command line and `run_started` is the audit trail of what was
  // actually selected.
  @Test
  func `an ad hoc showcase run records its normalized plan in run_started`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()

    let started = try await CapsuleDemosWorkspace.run(directory, [
      "showcase", "start", "--adhoc", "--select", "probe.core.alpha",
      "--idempotency-key", "adhoc-golden",
    ])

    #expect(started.isOk == true, Comment(rawValue: started.standardOutput))
    #expect(started.data.at("event.event_type")?.stringValue == "run_started")
    let selected = started.data.at("event.payload.plan.selected_items")?.arrayValue ?? []
    #expect(selected.count == 1)
    #expect(selected.first?["use_case_id"]?.stringValue == "probe.core.alpha")
  }

  // edge_no_capsule_file_is_left_behind. The whole point of "ad hoc" is that
  // nothing persists beyond the run's own event ledger.
  @Test
  func `an ad hoc run leaves no demo-capsules directory behind`() async throws {
    let directory = try CapsuleDemosWorkspace.make()

    _ = try await CapsuleDemosWorkspace.run(directory, [
      "showcase", "start", "--adhoc", "--select", "probe.core.alpha",
      "--idempotency-key", "adhoc-edge",
    ])

    #expect(!directory.exists("demo-capsules"), "no capsule file was created")
  }
}

//: @use-case:end capsule.demos.adhoc_release_demo#blackbox

//: @use-case:capsule.demos.runbook_not_proof#blackbox
/// The black-box oracle for capsule/demos.yml, row `runbook_not_proof`.
struct CapsuleRunbookNotProofTests {
  // golden_guard. The plan describes itself, explicitly, as prepared and not
  // performed — it is not left for the reader to infer.
  @Test
  func `a generated capsule plan describes itself as prepared, not performed`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )

    let planned = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )

    #expect(planned.data.at("plan_result.plan.prepared_not_performed")?.boolValue == true)
    let item = try #require(CapsuleDemosWorkspace.planItems(planned).first)
    let gap = (item["known_gaps"]?.arrayValue ?? []).contains { entry in
      entry["code"]?.stringValue == "prepared_not_performed"
        && entry["severity"]?.stringValue == "info"
    }
    #expect(gap)
  }

  // bad_a_capsule_never_becomes_evidence. Validate it, plan it, inspect it —
  // never run it — then ask the workspace's own composed proof view whether
  // anything counts. It must not.
  @Test
  func `a capsule only validated and planned never counts toward proof`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )

    _ = try await CapsuleDemosWorkspace.run(directory, ["capsule", "validate"])
    _ = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    _ = try await CapsuleDemosWorkspace.run(directory, ["capsule", "list"])

    let statused = try await CapsuleDemosWorkspace.run(directory, ["matrix", "status"])
    #expect(
      statused.data.at("evidence.counts.aggregates_active")?.intValue == 0,
      "no showcase run event was ever recorded",
    )
    let ledgers = statused.data.at("evidence.ledgers")?.arrayValue ?? []
    #expect(ledgers.isEmpty)
  }
}

//: @use-case:end capsule.demos.runbook_not_proof#blackbox
