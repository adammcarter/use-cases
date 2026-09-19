import Foundation
import Testing

//: @use-case:showcase.flow.live_acceptance_flow#blackbox
/// The black-box oracle for showcase/flow.yml, row `live_acceptance_flow`.
struct ShowcaseLiveAcceptanceTests {
  // golden_cli. The claim under test is "derived from events, not a summary
  // anyone wrote": prove it by reading status TWICE off the same ledger (a
  // cached/written summary could drift between reads; a replay cannot) and by
  // showing the run directory holds nothing but the ledger itself.
  @Test
  func `start, observe, pass a verdict, finish, and read status twice`() async throws {
    let directory = try ShowcaseWorkspace.make()
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "start",
    )

    let observed = try await ShowcaseWorkspace.observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "Watched the feature run live.",
      key: "obs",
    )
    #expect(observed.isOk == true)
    let recorded = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "verdict",
    )
    #expect(recorded.isOk == true)
    let finished = try await ShowcaseWorkspace.finish(directory, run: runIdentifier)
    #expect(finished.isOk == true)

    #expect(
      directory.files(under: ShowcaseWorkspace.runDirectory(runIdentifier)) == ["events.jsonl"],
      "the run directory must hold only the ledger, no summary file",
    )

    let firstRead = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    let secondRead = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(firstRead == secondRead)
    #expect(firstRead["execution_status"]?.stringValue == "completed")
    #expect(firstRead["run_outcome"]?.stringValue == "passed")
    let item = try #require(ShowcaseWorkspace.items(firstRead).first)
    #expect(item["verification_state"]?.stringValue == "requirements_met")
  }

  // bad_started_is_not_performed.
  @Test
  func `a started run derives prepared_not_performed and writes no summary`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make()
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "start-only",
    )

    #expect(
      directory.files(under: ShowcaseWorkspace.runDirectory(runIdentifier)) == ["events.jsonl"],
    )
    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(read["execution_status"]?.stringValue == "prepared_not_performed")
    #expect(read["run_outcome"]?.stringValue == "prepared_not_performed")
  }

  // edge_approval_binds_to_the_finish_event.
  @Test
  func `trusted approval requires a finished run and binds to the finish event`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "bind-start",
    )

    // Before finish: refused outright. There is no finish event yet for a
    // binding to name.
    let early = try await ShowcaseWorkspace.run(
      directory,
      ["showcase", "request-approval", "--repo", ".", "--run", runIdentifier],
    )
    #expect(early.isOk == false)
    #expect(early.diagnosticCodes.contains("showcase.finish_required_for_approval"))

    _ = try await ShowcaseWorkspace.observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "bind-obs",
    )
    _ = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "bind-verdict",
    )
    let finished = try await ShowcaseWorkspace.finish(directory, run: runIdentifier)
    let finishEventIdentifier = try #require(finished.data.at("event.event_id")?.stringValue)

    // Absent until an approval event exists.
    let pending = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(pending["approval_state"]?.stringValue == "pending")

    let afterFinish = try await ShowcaseWorkspace.run(
      directory,
      ["showcase", "request-approval", "--repo", ".", "--run", runIdentifier],
    )
    let request = try OracleJson.parse(afterFinish.standardOutput)
    #expect(
      request.at("binding.finish_event_id")?.stringValue == finishEventIdentifier,
      "the approval binding must name the finish event",
    )
  }
}

//: @use-case:end showcase.flow.live_acceptance_flow#blackbox

//: @use-case:showcase.flow.control_modes#blackbox
/// The black-box oracle for showcase/flow.yml, row `control_modes`.
struct ShowcaseControlModesTests {
  // golden_mixed. "Mixed" is reachable through the binary only at the verdict
  // layer (see the fixtures' header) — this proves that layer: the actor that
  // drove each verdict is the one the ledger names.
  @Test(arguments: ["agent", "user", "script"])
  func `the actor driving each verdict is recorded on the event`(actor: String) async throws {
    let performed = try await ShowcaseWorkspace.performUnderActor(actor, seed: actor)
    #expect(performed.recorded.isOk == true)
    #expect(performed.verifierType == actor)
  }

  // bad_agent_led_run_cannot_claim_user_approval.
  @Test
  func `an agent actor recording approval for a user-required plan is refused`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "agent-claim-start",
    )
    _ = try await ShowcaseWorkspace.observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "agent-claim-obs",
    )
    _ = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "agent-claim-verdict",
    )
    _ = try await ShowcaseWorkspace.finish(directory, run: runIdentifier)

    // No --actor (defaults to agent) and no --approval-token.
    let claimed = try await ShowcaseWorkspace.run(directory, [
      "showcase", "approve", "--repo", ".", "--run", runIdentifier,
      "--statement", "I approve my own demo.",
    ])
    #expect(claimed.isOk == false)
    #expect(claimed.envelope.diagnostics.encoded.contains("showcase.user_required_approval"))
    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(read["approval_state"]?.stringValue == "pending")
  }

  // edge_proof_semantics_do_not_change_with_the_driver.
  @Test(arguments: ["agent", "user", "script"])
  func `the derived status is identical whichever actor drove the same item`(
    actor: String,
  ) async throws {
    let performed = try await ShowcaseWorkspace.performUnderActor(actor, seed: "sem-\(actor)")
    #expect(performed.status["run_outcome"]?.stringValue == "passed")
    let item = try #require(ShowcaseWorkspace.items(performed.status).first)
    #expect(item["verdict"]?.stringValue == "pass")
    #expect(item["verification_state"]?.stringValue == "requirements_met")
  }
}

//: @use-case:end showcase.flow.control_modes#blackbox

//: @use-case:showcase.flow.status_separation#blackbox
/// The black-box oracle for showcase/flow.yml, row `status_separation`.
struct ShowcaseStatusSeparationTests {
  static func passedAndFinished(
    _ directory: TemporaryDirectory,
    seed: String,
  ) async throws -> String {
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "\(seed)-start",
    )
    _ = try await ShowcaseWorkspace.observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "\(seed)-obs",
    )
    _ = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "\(seed)-verdict",
    )
    _ = try await ShowcaseWorkspace.finish(directory, run: runIdentifier)
    return runIdentifier
  }

  // golden_status. Four axes, four separate fields — none derivable from any
  // of the others, which is this row's whole design point.
  @Test
  func `verdict, verification, run completion and approval read separately`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await Self.passedAndFinished(directory, seed: "sep")

    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    // Performed (completed) but unapproved (pending) is exactly the state this
    // row exists to make legible.
    #expect(read["execution_status"]?.stringValue == "completed")
    #expect(read["run_outcome"]?.stringValue == "passed")
    #expect(read["approval_state"]?.stringValue == "pending")
    let item = try #require(ShowcaseWorkspace.items(read).first)
    #expect(item["verdict"]?.stringValue == "pass")
    #expect(item["verification_state"]?.stringValue == "requirements_met")
  }

  // bad_states_are_never_collapsed.
  @Test
  func `passing every item with no user approval is never a single pass label`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await Self.passedAndFinished(directory, seed: "collapse")

    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(read["run_outcome"]?.stringValue == "passed")
    #expect(
      read["approval_state"]?.stringValue == "pending",
      "run_outcome:passed must not be read as acceptance while approval is pending",
    )
    #expect(read["result"] == nil)
    #expect(read["accepted"] == nil)
  }

  // edge_correction_changes_the_derived_status. Status is computed fresh from
  // the ledger every call, so correcting a verdict after finish moves it.
  @Test
  func `correcting a verdict after finish changes the derived status`() async throws {
    let directory = try ShowcaseWorkspace.make()
    let runIdentifier = try await ShowcaseWorkspace.startedRunIdentifier(
      directory,
      key: "recompute-start",
    )
    _ = try await ShowcaseWorkspace.observe(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      text: "obs",
      key: "recompute-obs",
    )
    let passed = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "pass",
      key: "recompute-verdict",
    )
    let verdictEventIdentifier = try #require(passed.data.at("event.event_id")?.stringValue)
    _ = try await ShowcaseWorkspace.finish(directory, run: runIdentifier)
    let beforeCorrection = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(beforeCorrection["run_outcome"]?.stringValue == "passed")

    let corrected = try await ShowcaseWorkspace.correct(
      directory,
      run: runIdentifier,
      targetEvent: verdictEventIdentifier,
      correction: .init(verdict: "fail", reason: "found a defect after the demo"),
      key: "recompute-correct",
    )
    #expect(corrected.isOk == true)

    let after = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(after["execution_status"]?.stringValue == "completed", "the run stays completed")
    #expect(
      after["run_outcome"]?.stringValue == "failed",
      "the outcome must move with the correction",
    )
    #expect(after["unresolved_failure_count"]?.intValue == 1)
  }
}

//: @use-case:end showcase.flow.status_separation#blackbox
