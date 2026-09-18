import Foundation
import Testing

/// The black-box oracle for showcase/flow.yml, row `failure_decisions`.
struct ShowcaseFailureDecisionsTests {
  /// Start a single-item run and record a failing verdict, answering the run
  /// and the verdict event that has to be decided about.
  static func failedItem(
    _ directory: TemporaryDirectory,
    seed: String,
  ) async throws -> (run: String, verdictEvent: String) {
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
    let failed = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.thing",
      verdict: "fail",
      key: "\(seed)-verdict",
    )
    return try (runIdentifier, #require(failed.data.at("event.event_id")?.stringValue))
  }

  /// A two-item run with BOTH items failed, and alpha's verdict event named.
  struct TwoFailingItems {
    let directory: TemporaryDirectory
    let run: String
    let alphaVerdictEvent: String
  }

  static func twoFailingItems() async throws -> TwoFailingItems {
    let directory = try ShowcaseWorkspace.makeMultiItem()
    let runIdentifier = try await ShowcaseWorkspace.startFromPlan(directory, key: "multi-start")
    for item in ["alpha", "beta"] {
      _ = try await ShowcaseWorkspace.observe(
        directory,
        run: runIdentifier,
        item: "item.probe.showcase.\(item)",
        text: "obs \(item)",
        key: "\(item)-obs",
      )
    }
    let alphaVerdict = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.alpha",
      verdict: "fail",
      key: "alpha-verdict",
    )
    _ = try await ShowcaseWorkspace.verdict(
      directory,
      run: runIdentifier,
      item: "item.probe.showcase.beta",
      verdict: "fail",
      key: "beta-verdict",
    )
    let alphaEvent = try #require(alphaVerdict.data.at("event.event_id")?.stringValue)
    return TwoFailingItems(
      directory: directory,
      run: runIdentifier,
      alphaVerdictEvent: alphaEvent,
    )
  }

  // golden_branch. "continue" is the branch that proves failed items are not
  // silently skipped: it clears the finish gate, but the failing verdict —
  // and therefore run_outcome:failed — stays exactly as recorded. Deciding to
  // continue is not deciding the failure did not happen.
  @Test
  func `deciding to continue past a failure clears the gate without hiding it`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make()
    let failed = try await Self.failedItem(directory, seed: "branch")

    let decided = try await ShowcaseWorkspace.decide(
      directory,
      run: failed.run,
      verdictEvent: failed.verdictEvent,
      decision: .init(kind: "continue", reason: "known issue, tracked separately"),
      key: "branch-decide",
    )
    #expect(decided.isOk == true)
    #expect(decided.data.at("status.unresolved_failure_count")?.intValue == 0)

    let finished = try await ShowcaseWorkspace.finish(directory, run: failed.run)
    #expect(finished.isOk == true, "the failure decision must clear the finish gate")
    #expect(finished.data.at("status.execution_status")?.stringValue == "completed")
    #expect(
      finished.data.at("status.run_outcome")?.stringValue == "failed",
      "continuing past a failure must not launder it into a pass",
    )
    let item = try #require(ShowcaseWorkspace.items(finished.data["status"] ?? .null).first)
    #expect(item["verdict"]?.stringValue == "fail")
  }

  // bad_failed_verdict_without_a_decision.
  @Test
  func `finishing with a failed verdict and no failure decision is refused`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make()
    let failed = try await Self.failedItem(directory, seed: "nodecision")

    let finished = try await ShowcaseWorkspace.finish(directory, run: failed.run)
    #expect(finished.isOk == false)
    #expect(
      finished.envelope.diagnostics.encoded.contains("showcase_failure_decision_required"),
    )
  }

  // edge_waiver_is_not_an_ordinary_pass.
  @Test
  func `waiving a failed item derives passed_with_waivers, never a pass`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make()
    let failed = try await Self.failedItem(directory, seed: "waive")

    _ = try await ShowcaseWorkspace.decide(
      directory,
      run: failed.run,
      verdictEvent: failed.verdictEvent,
      decision: .init(kind: "waive_with_reason", reason: "known flaky demo environment"),
      key: "waive-decide",
    )
    let finished = try await ShowcaseWorkspace.finish(directory, run: failed.run)
    #expect(finished.isOk == true)
    #expect(finished.data.at("status.run_outcome")?.stringValue == "passed_with_waivers")
    #expect(finished.data.at("status.run_outcome")?.stringValue != "passed")
    let item = try #require(ShowcaseWorkspace.items(finished.data["status"] ?? .null).first)
    #expect(item["verdict"]?.stringValue == "waived")
  }

  // edge_correction_resolves_only_the_targeted_failure.
  @Test
  func `correcting one failing item leaves the other failure untouched`()
    async throws
  {
    let both = try await Self.twoFailingItems()
    let (directory, runIdentifier) = (both.directory, both.run)
    let alphaEventIdentifier = both.alphaVerdictEvent

    let corrected = try await ShowcaseWorkspace.correct(
      directory,
      run: runIdentifier,
      targetEvent: alphaEventIdentifier,
      correction: .init(verdict: "pass", reason: "retested, alpha actually passed"),
      key: "alpha-correct",
    )
    #expect(corrected.isOk == true)
    let finalStatus = corrected.data["status"] ?? .null
    #expect(
      finalStatus["unresolved_failure_count"]?.intValue == 1,
      "correcting alpha must resolve only alpha's failure",
    )

    let alpha = try #require(
      ShowcaseWorkspace.item(finalStatus, identifier: "item.probe.showcase.alpha"),
    )
    let beta = try #require(
      ShowcaseWorkspace.item(finalStatus, identifier: "item.probe.showcase.beta"),
    )
    #expect(alpha["verdict"]?.stringValue == "pass")
    #expect(alpha["item_currency"]?.stringValue == "corrected")
    #expect(beta["verdict"]?.stringValue == "fail", "correcting alpha must never touch beta")
    #expect(beta["item_currency"]?.stringValue == "current")
  }
}

/// The black-box oracle for showcase/flow.yml, row
/// `revision_epoch_staleness` — which is not driveable through the binary.
///
/// NOT bound to this row on purpose. The core has the machinery —
/// appendShowcaseEpoch, and replay setting item_currency
/// "stale_due_to_epoch_change" — but NO CLI command ever calls it:
/// `use-cases showcase resume` takes no revision input and never appends an
/// epoch event. So the behaviour is real and unobservable from outside, which
/// is a contract gap to raise rather than a test to fake. Binding this row
/// would mark it verified against an oracle that asserts nothing.
///
/// `test.todo` in vitest; Swift Testing has no todo, so each is a disabled
/// test carrying the same reason — listed, skipped, and unable to go green by
/// accident.
struct ShowcaseRevisionEpochTests {
  @Test(.disabled("""
  golden_resume — resuming across a revision change marks affected verdicts stale: no CLI \
  command appends an epoch_started event (appendShowcaseEpoch is core-only, unreachable \
  from `use-cases showcase resume`)
  """))
  func `golden_resume — resuming across a revision change marks verdicts stale`() {
    Issue.record("unreachable: this test is disabled")
  }

  @Test(.disabled("""
  bad_old_verdicts_never_stay_silently_current — same missing affordance: staling verdicts \
  on a changed input has no CLI trigger
  """))
  func `bad_old_verdicts_never_stay_silently_current — no CLI trigger`() {
    Issue.record("unreachable: this test is disabled")
  }

  @Test(.disabled("""
  edge_stale_verdicts_are_rerun_or_carried_forward — same missing affordance: nothing can \
  produce a stale verdict through the CLI to rerun or carry forward
  """))
  func `edge_stale_verdicts_are_rerun_or_carried_forward — nothing produces one`() {
    Issue.record("unreachable: this test is disabled")
  }
}
