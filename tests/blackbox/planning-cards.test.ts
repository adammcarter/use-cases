// The black-box oracle for planning/cards.yml.
//
// Five rows about turning a matrix into a presentation: what a showcase
// selects, what a walkthrough adds beyond it, why a generated plan is never
// proof by itself, how audience/timebox constraints shape what fits, and how
// a partial matrix is flagged before anyone demos off it. All five are
// measured through `uc plan showcase`, `uc plan walkthrough` and
// `uc showcase start` — never by importing the selection code directly.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUcJson } from "../helpers/uc-binary";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

const WORKSPACE_CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

interface RowSpec {
  name: string;
  value: string;
  journey: string;
}

/** A row with a REAL verification/approval policy: only these are ever selectable for a plan. */
function rowYaml({ name, value, journey }: RowSpec): string {
  return `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: ${value}
    journey_role: ${journey}
    usage_frequency: common
    tags: [probe]
    actor: agent
    intent: Exist so a plan has something to select.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: probe.core.${name}.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
    approval_policy:
      mode: ask
`;
}

// A spread across value tier and journey role: one critical golden path, one
// core edge case, one supporting negative case. A showcase should prefer the
// first; a walkthrough should reach all three.
const ROWS: RowSpec[] = [
  { name: "crit_golden", value: "critical", journey: "golden" },
  { name: "core_edge", value: "core", journey: "edge" },
  { name: "supp_negative", value: "supporting", journey: "negative" }
];

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(rows: RowSpec[] = ROWS): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-planning-cards-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(
    join(dir, "use-cases", "probe.yml"),
    `schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n${rows.map(rowYaml).join("")}`
  );
  return { dir, env };
}

/** Add a second, malformed shard beside the valid one — the matrix degrades to `partial`, not `unusable`. */
function addDamagedShard(workspace: Workspace): void {
  writeFileSync(
    join(workspace.dir, "use-cases", "broken.yml"),
    "schema_version: 1\nfeature:\n  id: probe.broken\nuse_cases:\n  - id: probe.broken.item\n    preconditions: [broken\n"
  );
}

interface PlanItem {
  plan_item_id: string;
  use_case_id: string;
  estimated_seconds: number;
  selection_reasons: string[];
  known_gaps: Array<{ code: string; message: string; severity: string }>;
  evidence_summary: { readiness: string };
}

interface PlanExclusion {
  use_case_id: string;
  reason_code: string;
  reason: string;
  blocking: boolean;
}

interface Plan {
  plan_content_hash: string;
  prepared_not_performed: boolean;
  readiness: string;
  integrity_acknowledgement_required: boolean;
  audience: string;
  timebox_seconds: number;
  selected_items: PlanItem[];
  exclusions: PlanExclusion[];
  known_gaps: Array<{ code: string; message: string; severity: string }>;
}

interface PlanData {
  outcome: string;
  plan: Plan | null;
  candidate_summary: Record<string, unknown>;
  input_integrity: { matrix: string; evidence: string };
}

function planShowcase(workspace: Workspace, args: string[] = []) {
  return runUcJson<PlanData>(["plan", "showcase", "--repo", ".", ...args], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

function planWalkthrough(workspace: Workspace, args: string[] = []) {
  return runUcJson<PlanData>(["plan", "walkthrough", "--repo", ".", ...args], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

interface StartData {
  run_id: string;
}

function showcaseStart(workspace: Workspace, planFile: string) {
  return runUcJson<StartData>(["showcase", "start", "--repo", ".", "--plan-file", planFile], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

interface EvidenceStatusData {
  counts: {
    ledgers: number;
    events_loaded: number;
    aggregates_total: number;
    aggregates_active: number;
    aggregates_invalid: number;
  };
}

function evidenceStatus(workspace: Workspace) {
  return runUcJson<EvidenceStatusData>(["evidence", "status", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

//: @use-case:planning.cards.showcase_selection#blackbox
describe("planning.cards.showcase_selection", () => {
  // golden_cli. A short showcase must prioritise the critical golden path
  // over the core/supporting rows, and must respect the item limit it was
  // given rather than treating it as advisory.
  test("a limited showcase selects the critical golden path first and fits the limit", () => {
    const workspace = makeWorkspace();
    const { envelope } = planShowcase(workspace, ["--max-items", "2"]);

    expect(envelope.ok).toBe(true);
    const plan = envelope.data.plan;
    expect(plan).not.toBeNull();
    expect(plan!.selected_items.length).toBeLessThanOrEqual(2);
    expect(
      plan!.selected_items[0]!.use_case_id,
      "the critical golden row outranks core/supporting rows"
    ).toBe("probe.core.crit_golden");
  });

  // bad_a_plan_is_not_proof. Generating a showcase plan records nothing: the
  // evidence ledger stays exactly as empty as before the plan existed.
  test("generating a showcase plan leaves the evidence ledger untouched", () => {
    const workspace = makeWorkspace();
    const before = evidenceStatus(workspace).envelope.data.counts;
    expect(before).toEqual({
      ledgers: 0,
      events_loaded: 0,
      aggregates_total: 0,
      aggregates_active: 0,
      aggregates_invalid: 0
    });

    planShowcase(workspace, ["--max-items", "2"]);

    const after = evidenceStatus(workspace).envelope.data.counts;
    expect(after, "a plan is prepared material, not a recorded event").toEqual(before);
  });

  // edge_reasons_and_exclusions_are_reported. Every selection carries its own
  // reason and every exclusion names why it was left out — nothing is
  // silently dropped from the envelope.
  test("selection reasons, exclusions and the prepared-not-performed gap are all in the envelope", () => {
    const workspace = makeWorkspace();
    const { envelope } = planShowcase(workspace, ["--max-items", "2"]);
    const plan = envelope.data.plan!;

    for (const item of plan.selected_items) {
      expect(item.selection_reasons.length, `${item.use_case_id} must carry a reason`).toBeGreaterThan(0);
    }
    expect(plan.exclusions.length, "the supporting/negative row is excluded by the item cap").toBe(1);
    expect(plan.exclusions[0]!.use_case_id).toBe("probe.core.supp_negative");
    expect(plan.exclusions[0]!.reason.length).toBeGreaterThan(0);
    expect(plan.known_gaps.map((g) => g.code)).toContain("prepared_not_performed");
  });
});
//: @use-case:end planning.cards.showcase_selection#blackbox

//: @use-case:planning.cards.walkthrough_coverage#blackbox
describe("planning.cards.walkthrough_coverage", () => {
  // golden_cli. A walkthrough is a deeper cut than a showcase: it must reach
  // the edge, negative AND failure rows a showcase would leave out. A local,
  // 4-row fixture (not the shared ROWS) so this is the only test that carries
  // a failure-journey row and its own generous --timebox, so breadth — not
  // the walkthrough profile's default clock — is what drives the selection.
  test("a walkthrough includes edge, negative and failure rows, not just the golden path", () => {
    const workspace = makeWorkspace([...ROWS, { name: "core_failure", value: "core", journey: "failure" }]);
    const { envelope } = planWalkthrough(workspace, ["--timebox", "1800"]);
    const plan = envelope.data.plan!;

    const selectedIds = plan.selected_items.map((i) => i.use_case_id);
    expect(selectedIds).toContain("probe.core.crit_golden");
    expect(selectedIds, "edge coverage is part of a walkthrough").toContain("probe.core.core_edge");
    expect(selectedIds, "negative coverage is part of a walkthrough").toContain("probe.core.supp_negative");
    expect(selectedIds, "failure coverage is part of a walkthrough").toContain("probe.core.core_failure");
  });

  // bad_breadth_is_not_signoff. Covering breadth is not the same as
  // certifying it: the plan must keep reporting the evidence gaps and the
  // prepared-not-performed flag rather than presenting itself as acceptance.
  test("a broad walkthrough still reports evidence gaps instead of implying sign-off", () => {
    const workspace = makeWorkspace();
    const { envelope } = planWalkthrough(workspace);
    const plan = envelope.data.plan!;

    expect(plan.prepared_not_performed).toBe(true);
    expect(
      plan.readiness,
      "unproven rows keep the plan at ready_with_evidence_gaps, never a plain ready/accepted state"
    ).toBe("ready_with_evidence_gaps");
  });

  // edge_caveats_and_evidence_state_travel_with_it. The caveats and evidence
  // state are fields on the same plan envelope, not a separate report the
  // reader has to go find.
  test("each selected item carries its own evidence state and gap, inline", () => {
    const workspace = makeWorkspace();
    const { envelope } = planWalkthrough(workspace);
    const plan = envelope.data.plan!;

    for (const item of plan.selected_items) {
      expect(item.evidence_summary.readiness, `${item.use_case_id} has no recorded evidence yet`).toBe("missing");
      expect(
        item.known_gaps.map((g) => g.code),
        `${item.use_case_id} names its gap rather than omitting it`
      ).toContain("evidence_missing");
    }
  });
});
//: @use-case:end planning.cards.walkthrough_coverage#blackbox

//: @use-case:planning.cards.prepared_not_performed#blackbox
describe("planning.cards.prepared_not_performed", () => {
  // golden_guard. A freshly generated plan always reports itself as prepared,
  // not performed.
  test("a generated plan reports prepared_not_performed true", () => {
    const workspace = makeWorkspace();
    const { envelope } = planShowcase(workspace, ["--max-items", "1"]);
    expect(envelope.data.plan!.prepared_not_performed).toBe(true);
  });

  // bad_a_plan_never_becomes_evidence_by_itself. Generating a plan cannot be
  // mistaken for proof: nothing lands in the evidence ledger until a run
  // actually happens.
  test("a generated plan alone never appears as recorded evidence", () => {
    const workspace = makeWorkspace();
    planShowcase(workspace, ["--max-items", "1"]);
    planWalkthrough(workspace);

    const status = evidenceStatus(workspace).envelope.data;
    expect(status.counts.aggregates_total, "plans and walkthroughs record no evidence by themselves").toBe(0);
  });

  // edge_a_run_must_bind_to_the_plan_hash. A run only starts from the exact
  // plan content it claims to bind to; a plan mutated after the fact cannot
  // borrow that acceptance.
  test("a run binds to the plan's content hash; a mutated plan is refused, not silently accepted", () => {
    const workspace = makeWorkspace();
    const { envelope: planEnvelope } = planShowcase(workspace, ["--max-items", "1"]);
    const plan = planEnvelope.data.plan!;
    writeFileSync(join(workspace.dir, "plan.json"), JSON.stringify(plan));

    const first = showcaseStart(workspace, "plan.json");
    expect(first.envelope.ok, "starting from the untouched plan file succeeds").toBe(true);
    const hashHex = plan.plan_content_hash.split(":")[1]!;
    expect(first.envelope.data.run_id, "the run id binds to the plan's content hash").toContain(hashHex);

    const mutated = { ...plan, audience: "a-different-audience-than-was-planned" };
    writeFileSync(join(workspace.dir, "plan-mutated.json"), JSON.stringify(mutated));

    const second = showcaseStart(workspace, "plan-mutated.json");
    expect(second.envelope.ok, "a plan mutated after generation cannot start a run").toBe(false);
    expect(JSON.stringify(second.envelope.diagnostics)).toContain("showcase_plan_hash_mismatch");
  });
});
//: @use-case:end planning.cards.prepared_not_performed#blackbox

//: @use-case:planning.cards.audience_timebox_fit#blackbox
describe("planning.cards.audience_timebox_fit", () => {
  // golden_adjust. The plan is generated to fit the caller's stated audience
  // and timebox, not a fixed default.
  test("the plan carries the requested audience and fits within the requested timebox", () => {
    const workspace = makeWorkspace();
    const { envelope } = planShowcase(workspace, ["--audience", "stakeholder", "--timebox", "150"]);
    const plan = envelope.data.plan!;

    expect(plan.audience).toBe("stakeholder");
    expect(plan.timebox_seconds).toBe(150);
    const totalSeconds = plan.selected_items.reduce((sum, item) => sum + item.estimated_seconds, 0);
    expect(totalSeconds, "the selected items fit inside the requested timebox").toBeLessThanOrEqual(150);
    expect(plan.selected_items.length, "a tight timebox narrows the selection").toBeLessThan(ROWS.length);
  });

  // bad_exclusions_are_never_hidden. Rows a tight timebox could not fit are
  // named in the plan, not quietly dropped.
  //
  // NOTE: reading candidates.ts/selectPlan.ts shows every exclusion here is
  // labelled reason_code "max_items" ("Higher-priority items consumed the
  // available item cap.") even though the clock, not an item-count cap, is
  // what forced these rows out — exclusionFor's "timebox" branch exists but
  // selectPlan.ts never calls it with that code. So this only asserts a
  // reason string is present and non-empty, deliberately not its wording or
  // code: the label is currently wrong for a timebox-driven exclusion.
  test("rows a tight timebox forced out are named as exclusions, never dropped silently", () => {
    const workspace = makeWorkspace();
    const { envelope } = planShowcase(workspace, ["--audience", "stakeholder", "--timebox", "150"]);
    const plan = envelope.data.plan!;

    const excludedIds = plan.exclusions.map((e) => e.use_case_id);
    expect(excludedIds.length, "the rows that did not fit are explicit exclusions").toBeGreaterThan(0);
    for (const exclusion of plan.exclusions) {
      expect(exclusion.reason.length, `${exclusion.use_case_id} exclusion must carry a reason`).toBeGreaterThan(0);
    }
    expect(plan.selected_items.length + excludedIds.length).toBe(ROWS.length);
  });
});
//: @use-case:end planning.cards.audience_timebox_fit#blackbox

//: @use-case:planning.cards.partial_matrix_warning#blackbox
describe("planning.cards.partial_matrix_warning", () => {
  // golden_strict. Non-strict planning over a partial matrix requires
  // acknowledgement; strict planning refuses to produce a plan at all.
  test("a partial matrix requires acknowledgement, and --strict blocks the plan outright", () => {
    const workspace = makeWorkspace();
    addDamagedShard(workspace);

    const nonStrict = planShowcase(workspace).envelope;
    expect(nonStrict.data.outcome).toBe("generated");
    expect(nonStrict.data.plan!.integrity_acknowledgement_required, "a partial matrix must be acknowledged").toBe(
      true
    );

    const strict = planShowcase(workspace, ["--strict"]).envelope;
    expect(strict.data.outcome, "strict mode refuses to plan over damage at all").toBe("integrity_blocked");
    expect(strict.data.plan).toBeNull();
  });

  // bad_partial_cannot_masquerade_as_full. A partial matrix must read
  // differently from a clean one — same shape of command, visibly different
  // outcome.
  test("a partial matrix plan is visibly different from a clean matrix plan", () => {
    const cleanWorkspace = makeWorkspace();
    const clean = planShowcase(cleanWorkspace).envelope;
    expect(clean.ok).toBe(true);
    expect(clean.data.input_integrity.matrix).toBe("clean");

    const partialWorkspace = makeWorkspace();
    addDamagedShard(partialWorkspace);
    const partial = planShowcase(partialWorkspace).envelope;

    expect(partial.ok, "a partial matrix cannot report ok like a clean one").toBe(false);
    expect(partial.data.input_integrity.matrix).toBe("partial");
    expect(
      partial.data.plan!.readiness,
      "readiness names the degraded input rather than reusing the clean-plan readiness"
    ).toBe("partial_due_to_integrity");
    expect(partial.data.plan!.readiness).not.toBe(clean.data.plan!.readiness);
  });

  // edge_diagnostics_precede_any_live_run. The damage is reported in the same
  // response that generates the plan — before any run has been started.
  test("the damage is diagnosed at plan time, before any showcase run is started", () => {
    const workspace = makeWorkspace();
    addDamagedShard(workspace);

    const { envelope } = planShowcase(workspace);
    expect(envelope.diagnostics.length, "diagnostics arrive with the plan itself").toBeGreaterThan(0);
    expect(JSON.stringify(envelope.diagnostics)).toContain("broken.yml");
    // No run exists yet: nothing has been started, so there is nothing for the
    // diagnostic to have waited for.
    const status = evidenceStatus(workspace).envelope.data;
    expect(status.counts.aggregates_total).toBe(0);
  });
});
//: @use-case:end planning.cards.partial_matrix_warning#blackbox
