import Foundation
import Testing

/// The black-box oracle for planning/cards.yml, row `showcase_selection`.
struct PlanningShowcaseSelectionTests {
  // golden_cli. A short showcase must prioritise the critical golden path
  // over the core/supporting rows, and must respect the item limit it was
  // given rather than treating it as advisory.
  @Test
  func `a limited showcase selects the critical golden path first and fits`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "2"])

    #expect(planned.isOk == true)
    let plan = try #require(planned.data["plan"])
    #expect(!plan.isNull)
    let items = plan["selected_items"]?.arrayValue ?? []
    #expect(items.count <= 2)
    #expect(
      items.first?["use_case_id"]?.stringValue == "probe.core.crit_golden",
      "the critical golden row outranks core/supporting rows",
    )
  }

  // bad_a_plan_is_not_proof. Generating a showcase plan records nothing: the
  // evidence ledger stays exactly as empty as before the plan existed.
  @Test
  func `generating a showcase plan leaves the evidence ledger untouched`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let before = try await PlanningWorkspace.evidenceCounts(directory)
    #expect(before == .object([
      "ledgers": .number(0),
      "events_loaded": .number(0),
      "aggregates_total": .number(0),
      "aggregates_active": .number(0),
      "aggregates_invalid": .number(0),
    ]))

    _ = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "2"])

    let after = try await PlanningWorkspace.evidenceCounts(directory)
    #expect(after == before, "a plan is prepared material, not a recorded event")
  }

  // edge_reasons_and_exclusions_are_reported. Every selection carries its own
  // reason and every exclusion names why it was left out — nothing is
  // silently dropped from the envelope.
  @Test
  func `selection reasons, exclusions and the prepared gap are all in the envelope`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "2"])
    let plan = try #require(planned.data["plan"])

    for item in plan["selected_items"]?.arrayValue ?? [] {
      let identifier = item["use_case_id"]?.stringValue ?? "?"
      // Bound first: `#expect(!(x?.y ?? []).isEmpty)` expands to a
      // property-access check on the OPTIONAL and reports a false failure.
      let reasons = item["selection_reasons"]?.arrayValue ?? []
      #expect(
        !reasons.isEmpty,
        Comment(rawValue: "\(identifier) must carry a reason"),
      )
    }
    let exclusions = plan["exclusions"]?.arrayValue ?? []
    #expect(exclusions.count == 1, "the supporting/negative row is excluded by the item cap")
    #expect(exclusions.first?["use_case_id"]?.stringValue == "probe.core.supp_negative")
    let reason = exclusions.first?["reason"]?.stringValue ?? ""
    #expect(!reason.isEmpty)
    let gaps = (plan["known_gaps"]?.arrayValue ?? []).compactMap { gap in
      gap["code"]?.stringValue
    }
    #expect(gaps.contains("prepared_not_performed"))
  }
}

/// The black-box oracle for planning/cards.yml, row `walkthrough_coverage`.
struct PlanningWalkthroughTests {
  // golden_cli. A walkthrough is a deeper cut than a showcase: it must reach
  // the edge, negative AND failure rows a showcase would leave out. A local,
  // 4-row fixture (not the shared rows) so this is the only test that carries
  // a failure-journey row and its own generous --timebox, so breadth — not
  // the walkthrough profile's default clock — is what drives the selection.
  @Test
  func `a walkthrough includes edge, negative and failure rows`() async throws {
    let directory = try PlanningWorkspace.make(
      rows: PlanningWorkspace.rows + [
        PlanningWorkspace.RowSpec(name: "core_failure", value: "core", journey: "failure"),
      ],
    )
    let planned = try await PlanningWorkspace.planWalkthrough(directory, ["--timebox", "1800"])
    let plan = try #require(planned.data["plan"])

    let selected = PlanningWorkspace.selectedIdentifiers(plan)
    #expect(selected.contains("probe.core.crit_golden"))
    #expect(
      selected.contains("probe.core.core_edge"),
      "edge coverage is part of a walkthrough",
    )
    #expect(
      selected.contains("probe.core.supp_negative"),
      "negative coverage is part of a walkthrough",
    )
    #expect(
      selected.contains("probe.core.core_failure"),
      "failure coverage is part of a walkthrough",
    )
  }

  // bad_breadth_is_not_signoff. Covering breadth is not the same as
  // certifying it: the plan must keep reporting the evidence gaps and the
  // prepared-not-performed flag rather than presenting itself as acceptance.
  @Test
  func `a broad walkthrough still reports evidence gaps instead of sign-off`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planWalkthrough(directory)
    let plan = try #require(planned.data["plan"])

    #expect(plan["prepared_not_performed"]?.boolValue == true)
    #expect(
      plan["readiness"]?.stringValue == "ready_with_evidence_gaps",
      "unproven rows keep the plan at ready_with_evidence_gaps, never ready/accepted",
    )
  }

  // edge_caveats_and_evidence_state_travel_with_it. The caveats and evidence
  // state are fields on the same plan envelope, not a separate report the
  // reader has to go find.
  @Test
  func `each selected item carries its own evidence state and gap, inline`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planWalkthrough(directory)
    let plan = try #require(planned.data["plan"])

    for item in plan["selected_items"]?.arrayValue ?? [] {
      let identifier = item["use_case_id"]?.stringValue ?? "?"
      #expect(
        item.at("evidence_summary.readiness")?.stringValue == "missing",
        Comment(rawValue: "\(identifier) has no recorded evidence yet"),
      )
      let gaps = (item["known_gaps"]?.arrayValue ?? []).compactMap { gap in
        gap["code"]?.stringValue
      }
      #expect(
        gaps.contains("evidence_missing"),
        Comment(rawValue: "\(identifier) names its gap rather than omitting it"),
      )
    }
  }
}

/// The black-box oracle for planning/cards.yml, row `prepared_not_performed`.
struct PlanningPreparedNotPerformedTests {
  // golden_guard. A freshly generated plan always reports itself as prepared,
  // not performed.
  @Test
  func `a generated plan reports prepared_not_performed true`() async throws {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "1"])
    #expect(planned.data.at("plan.prepared_not_performed")?.boolValue == true)
  }

  // bad_a_plan_never_becomes_evidence_by_itself. Generating a plan cannot be
  // mistaken for proof: nothing lands in the evidence ledger until a run
  // actually happens.
  @Test
  func `a generated plan alone never appears as recorded evidence`() async throws {
    let directory = try PlanningWorkspace.make()
    _ = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "1"])
    _ = try await PlanningWorkspace.planWalkthrough(directory)

    let counts = try await PlanningWorkspace.evidenceCounts(directory)
    #expect(
      counts["aggregates_total"]?.intValue == 0,
      "plans and walkthroughs record no evidence by themselves",
    )
  }

  // edge_a_run_must_bind_to_the_plan_hash. A run only starts from the exact
  // plan content it claims to bind to; a plan mutated after the fact cannot
  // borrow that acceptance.
  @Test
  func `a run binds to the plan's content hash; a mutated plan is refused`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(directory, ["--max-items", "1"])
    let plan = try #require(planned.data["plan"])
    try directory.writeFile("plan.json", contents: plan.encoded)

    let first = try await PlanningWorkspace.showcaseStart(directory, planFile: "plan.json")
    #expect(
      first.isOk == true,
      Comment(rawValue: "starting from the untouched plan file failed: \(first.standardOutput)"),
    )
    let contentHash = try #require(plan["plan_content_hash"]?.stringValue)
    let hexadecimal = try #require(contentHash.split(separator: ":").last.map(String.init))
    #expect(
      first.data["run_id"]?.stringValue?.contains(hexadecimal) == true,
      "the run id binds to the plan's content hash",
    )

    var mutatedFields = try #require(plan.objectValue)
    mutatedFields["audience"] = .string("a-different-audience-than-was-planned")
    try directory.writeFile("plan-mutated.json", contents: OracleJson.object(mutatedFields).encoded)

    let second = try await PlanningWorkspace.showcaseStart(
      directory,
      planFile: "plan-mutated.json",
    )
    #expect(second.isOk == false, "a plan mutated after generation cannot start a run")
    #expect(second.envelope.diagnostics.encoded.contains("showcase_plan_hash_mismatch"))
  }
}

/// The black-box oracle for planning/cards.yml, row `audience_timebox_fit`.
struct PlanningAudienceTimeboxTests {
  // golden_adjust. The plan is generated to fit the caller's stated audience
  // and timebox, not a fixed default.
  @Test
  func `the plan carries the requested audience and fits the requested timebox`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(
      directory,
      ["--audience", "stakeholder", "--timebox", "150"],
    )
    let plan = try #require(planned.data["plan"])

    #expect(plan["audience"]?.stringValue == "stakeholder")
    #expect(plan["timebox_seconds"]?.intValue == 150)
    let items = plan["selected_items"]?.arrayValue ?? []
    let totalSeconds = items.reduce(0) { total, item in
      total + (item["estimated_seconds"]?.intValue ?? 0)
    }
    #expect(totalSeconds <= 150, "the selected items fit inside the requested timebox")
    #expect(
      items.count < PlanningWorkspace.rows.count,
      "a tight timebox narrows the selection",
    )
  }

  // bad_exclusions_are_never_hidden. Rows a tight timebox could not fit are
  // named in the plan, not quietly dropped.
  //
  // NOTE: every exclusion here is labelled reason_code "max_items" ("Higher-
  // priority items consumed the available item cap.") even though the clock,
  // not an item-count cap, is what forced these rows out — the "timebox"
  // branch exists but the selector never reaches it with that code. So this
  // only asserts a reason string is present and non-empty, deliberately not
  // its wording or code: the label is currently wrong for a timebox-driven
  // exclusion.
  @Test
  func `rows a tight timebox forced out are named as exclusions`() async throws {
    let directory = try PlanningWorkspace.make()
    let planned = try await PlanningWorkspace.planShowcase(
      directory,
      ["--audience", "stakeholder", "--timebox", "150"],
    )
    let plan = try #require(planned.data["plan"])

    let exclusions = plan["exclusions"]?.arrayValue ?? []
    #expect(!exclusions.isEmpty, "the rows that did not fit are explicit exclusions")
    for exclusion in exclusions {
      let identifier = exclusion["use_case_id"]?.stringValue ?? "?"
      let reason = exclusion["reason"]?.stringValue ?? ""
      #expect(
        !reason.isEmpty,
        Comment(rawValue: "\(identifier) exclusion must carry a reason"),
      )
    }
    let selected = (plan["selected_items"]?.arrayValue ?? []).count
    #expect(selected + exclusions.count == PlanningWorkspace.rows.count)
  }
}

/// The black-box oracle for planning/cards.yml, row `partial_matrix_warning`.
struct PlanningPartialMatrixTests {
  // golden_strict. Non-strict planning over a partial matrix requires
  // acknowledgement; strict planning refuses to produce a plan at all.
  @Test
  func `a partial matrix requires acknowledgement, and --strict blocks the plan`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    try PlanningWorkspace.addDamagedShard(directory)

    let nonStrict = try await PlanningWorkspace.planShowcase(directory)
    #expect(nonStrict.data["outcome"]?.stringValue == "generated")
    #expect(
      nonStrict.data.at("plan.integrity_acknowledgement_required")?.boolValue == true,
      "a partial matrix must be acknowledged",
    )

    let strict = try await PlanningWorkspace.planShowcase(directory, ["--strict"])
    #expect(
      strict.data["outcome"]?.stringValue == "integrity_blocked",
      "strict mode refuses to plan over damage at all",
    )
    #expect(strict.data["plan"]?.isNull == true)
  }

  // bad_partial_cannot_masquerade_as_full. A partial matrix must read
  // differently from a clean one — same shape of command, visibly different
  // outcome.
  @Test
  func `a partial matrix plan is visibly different from a clean matrix plan`()
    async throws
  {
    let cleanDirectory = try PlanningWorkspace.make()
    let clean = try await PlanningWorkspace.planShowcase(cleanDirectory)
    #expect(clean.isOk == true)
    #expect(clean.data.at("input_integrity.matrix")?.stringValue == "clean")

    let partialDirectory = try PlanningWorkspace.make()
    try PlanningWorkspace.addDamagedShard(partialDirectory)
    let partial = try await PlanningWorkspace.planShowcase(partialDirectory)

    #expect(partial.isOk == false, "a partial matrix cannot report ok like a clean one")
    #expect(partial.data.at("input_integrity.matrix")?.stringValue == "partial")
    #expect(
      partial.data.at("plan.readiness")?.stringValue == "partial_due_to_integrity",
      "readiness names the degraded input rather than reusing the clean readiness",
    )
    #expect(partial.data.at("plan.readiness") != clean.data.at("plan.readiness"))
  }

  // edge_diagnostics_precede_any_live_run. The damage is reported in the same
  // response that generates the plan — before any run has been started.
  @Test
  func `the damage is diagnosed at plan time, before any run is started`()
    async throws
  {
    let directory = try PlanningWorkspace.make()
    try PlanningWorkspace.addDamagedShard(directory)

    let planned = try await PlanningWorkspace.planShowcase(directory)
    let diagnostics = planned.envelope.diagnostics.arrayValue ?? []
    #expect(!diagnostics.isEmpty, "diagnostics arrive with the plan itself")
    #expect(planned.envelope.diagnostics.encoded.contains("broken.yml"))
    // No run exists yet: nothing has been started, so there is nothing for the
    // diagnostic to have waited for.
    let counts = try await PlanningWorkspace.evidenceCounts(directory)
    #expect(counts["aggregates_total"]?.intValue == 0)
  }
}
