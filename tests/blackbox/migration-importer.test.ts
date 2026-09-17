// The black-box oracle for migration/importer.yml.
//
// This is the same `uc migrate test-matrix` surface as
// migration-test-matrix.test.ts, but it exercises the review-boundary claims
// the importer row makes: drafts stay auditable back to source, a legacy
// PASS/DONE/accepted mark never becomes evidence, and (per the row) a human
// reviews a feature printout before anything activates. The last claim does
// not survive contact with the binary — see the row-4 describe block below,
// which documents the measured disagreement instead of faking a pass.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
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

// A complete seed row: an empty `use_cases: []` fails schema.minItems and
// leaves the whole matrix unusable.
const SEEDED_MATRIX = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.alpha
    title: Alpha
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so the matrix is valid.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: probe.core.alpha.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

// Three legacy rows chosen so each review-warning code fires at least once:
// AUTH-1 is a complete row carrying a legacy PASS; AUTH-2 has legacy evidence
// text but no expected outcome; AUTH-3 has neither a scenario nor steps (so
// it is ambiguous) and legacy sign-off wording in its notes.
const LEGACY = `# Test matrix

| ID | Scenario | Steps | Expected | Status | Evidence | Notes |
|----|----------|-------|----------|--------|----------|-------|
| AUTH-1 | User signs in with valid credentials | Enter valid credentials; Submit the form | User is signed in and redirected to the dashboard | PASS |  |  |
| AUTH-2 | Sign-in rejects a bad password | Enter an invalid password; Submit the form |  | DONE | screenshot.png |  |
| AUTH-3 |  |  |  | accepted |  | Signed off by QA lead |
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-migration-importer-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), SEEDED_MATRIX);
  writeFileSync(join(dir, "TEST-MATRIX.md"), LEGACY);
  return { dir, env };
}

interface MigrationData {
  mode: string;
  source: { path: string; digest: string; parser: string };
  summary: Record<string, number>;
  would_write: Array<{ path: string; action: string }>;
  warnings: Array<{ code: string; message: string; row_ref: string | null }>;
  drafts: Array<{ output_path: string; feature_id: string; use_case_ids: string[]; content: string }>;
}

function migrate(workspace: Workspace, extra: string[]) {
  return runUcJson<MigrationData>(
    ["migrate", "test-matrix", "--repo", ".", "--source", "TEST-MATRIX.md", "--out", "use-cases/_migrated", ...extra],
    { cwd: workspace.dir, env: workspace.env }
  );
}

interface EvidenceStatusData {
  counts: { ledgers: number; events_loaded: number; aggregates_total: number; aggregates_active: number };
}

function evidenceStatus(workspace: Workspace) {
  return runUcJson<EvidenceStatusData>(["evidence", "status", "--repo", "."], { cwd: workspace.dir, env: workspace.env });
}

function migratedFiles(workspace: Workspace): string[] {
  try {
    return readdirSync(join(workspace.dir, "use-cases", "_migrated"));
  } catch {
    return [];
  }
}

//: @use-case:migration.importer.reviewable_draft_import#blackbox
describe("migration.importer.reviewable_draft_import", () => {
  // golden_dry_run. A dry run must be safe to point at someone's real repo,
  // and it must hand back both the generated drafts and the diagnostics a
  // reviewer needs to judge them.
  test("a dry run inspects the generated draft rows and their diagnostics", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    expect(envelope.ok).toBe(true);
    expect(envelope.data.mode).toBe("dry_run");
    expect(envelope.data.summary.rows_seen).toBe(3);
    expect(envelope.data.summary.files_written).toBe(0);
    expect(envelope.data.drafts.length).toBeGreaterThan(0);
    expect(envelope.data.warnings.length, "diagnostics must accompany the draft").toBeGreaterThan(0);
    expect(migratedFiles(workspace), "a preview must leave the disk alone").toEqual([]);
  });

  // bad_import_is_never_silently_active. Measured, not guessed: a legacy row
  // with a clear scenario AND an expected outcome comes out with
  // `lifecycle: active`, not `planned`, regardless of its legacy status. A
  // subsequent `uc matrix validate --repo .` on the written output returns
  // ok:true / complete:true with zero diagnostics — the matrix accepts that
  // active row with no review step and no evidence at all. AUTH-1 above (a
  // legacy PASS row with complete scenario/expected text) reproduces this
  // every run. That directly contradicts this scenario's claim that "an
  // import cannot produce an active row" — it can, and does, whenever the
  // legacy row happens to already read like a complete use case. There is no
  // CLI-observable "review before activation" gate on this path to assert
  // instead.
  test.todo(
    "bad_import_is_never_silently_active — FALSE per the binary: a legacy row with both a scenario and an expected outcome is drafted with lifecycle: active (see migrateTestMatrix's clearBehavior branch in packages/core/src/migration/testMatrix.ts), and `uc matrix validate` accepts it with zero diagnostics. Migration CAN grant silent active status; there is no observable gate to test instead."
  );

  // edge_review_warnings_name_what_is_ambiguous. A reviewer has to be able to
  // tell, from the warnings alone, which rows need a closer look and why.
  test("review warnings name ambiguous titles, old statuses, and missing detail", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    const codes = envelope.data.warnings.map((w) => w.code);
    expect(codes, "a legacy status mark is called out").toContain("old_status_not_evidence");
    expect(codes, "a row missing an expected outcome is called out").toContain("missing_expected_outcome");
    expect(codes, "a row with neither a scenario nor steps is called out as ambiguous").toContain("ambiguous_row");

    const ambiguous = envelope.data.warnings.find((w) => w.code === "ambiguous_row");
    expect(ambiguous?.row_ref, "the ambiguous warning names the exact source row").toContain("table-1-row-3");
  });
});
//: @use-case:end migration.importer.reviewable_draft_import#blackbox

//: @use-case:migration.importer.no_legacy_pass_as_proof#blackbox
describe("migration.importer.no_legacy_pass_as_proof", () => {
  // golden_guard. Whatever the source said, the generated document must
  // mint nothing that looks like proof.
  test("generated rows carry no evidence ids, regardless of legacy status", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    expect(envelope.data.warnings.map((w) => w.code)).toContain("old_status_not_evidence");
    for (const draft of envelope.data.drafts) {
      expect(draft.content, "no draft may reference an evidence id").not.toMatch(/evidence_id/);
    }
  });

  // bad_an_old_pass_mark_never_becomes_evidence. Import the PASS/DONE/accepted
  // rows for real, then ask the evidence ledger itself whether anything was
  // recorded — not just whether the draft text avoids the word "evidence".
  test("an old pass mark never becomes evidence in the ledger", () => {
    const workspace = makeWorkspace();
    const written = migrate(workspace, ["--write"]).envelope;
    expect(written.ok).toBe(true);

    const status = evidenceStatus(workspace).envelope;
    expect(status.data.counts.events_loaded, "migration must not append to the evidence ledger").toBe(0);
    expect(status.data.counts.aggregates_total, "nothing counts as current proof for the migrated rows").toBe(0);
  });

  // edge_old_status_survives_as_review_context. The legacy mark should still
  // be readable — as context, in a place that cannot be mistaken for proof.
  test("old status survives only as review context, never as an evidence field", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    const draft = envelope.data.drafts[0].content;
    expect(draft, "the legacy status is preserved under the migration extension").toContain("legacy_status: PASS");
    expect(draft, "it is never surfaced as an evidence field").not.toMatch(/^\s*evidence:/m);

    const warning = envelope.data.warnings.find((w) => w.code === "old_status_not_evidence");
    expect(warning?.message).toMatch(/did not create evidence/);
  });
});
//: @use-case:end migration.importer.no_legacy_pass_as_proof#blackbox

//: @use-case:migration.importer.source_traceability#blackbox
describe("migration.importer.source_traceability", () => {
  // golden_refs. Every generated row must point back at the exact source
  // table and row it came from.
  test("migration output can be audited against its source", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    expect(envelope.data.source.path).toBe("TEST-MATRIX.md");
    expect(envelope.data.source.digest).toMatch(/^sha256:/);

    const draft = envelope.data.drafts[0].content;
    expect(draft).toContain("path: TEST-MATRIX.md#table-1-row-1");
    expect(draft).toContain("path: TEST-MATRIX.md#table-1-row-2");
    expect(draft).toContain("path: TEST-MATRIX.md#table-1-row-3");
  });

  // edge_a_reviewer_can_compare_row_to_source_intent. Take one generated row
  // and confirm its content actually matches the markdown row named in its
  // own source_ref, word for word.
  test("a reviewer can trace a generated row back to its source row's own text", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    const draft = envelope.data.drafts[0].content;
    // AUTH-1's own row_ref names table 1, row 1 — the same row whose
    // "Scenario" and "Expected" cells are reproduced verbatim below it.
    expect(draft).toContain("path: TEST-MATRIX.md#table-1-row-1");
    expect(draft).toContain("title: User signs in with valid credentials");
    expect(draft).toContain("intent: User signs in with valid credentials");
    expect(draft).toContain("User is signed in and redirected to the dashboard");
    expect(draft, "the legacy id from the same source row is preserved alongside it").toContain("legacy_id: AUTH-1");
  });
});
//: @use-case:end migration.importer.source_traceability#blackbox

// NOT bound to this row on purpose. All three of its scenarios are todo — there
// is no CLI review/printout/activate step to drive — so binding it would mark
// the row verified against an oracle that asserts nothing. The todos below
// record what the row claims and why it cannot be proven.
describe("migration.importer.human_review_activation", () => {
  // golden_review. There is no CLI command that presents a feature printout,
  // asks the user to confirm scope, and then activates only what was
  // reviewed. `uc migrate test-matrix` has exactly two modes, --dry-run and
  // --write, and neither one pauses for a human decision — docs/migration.md
  // only asks the human, by convention, to keep files under
  // use-cases/_migrated/ "until a human reviews and reshapes them"; nothing
  // enforces that. This step is a human/product workflow outside the binary.
  test.todo(
    "golden_review — not drivable through the binary: there is no `uc migrate` review/printout/confirm/activate step. docs/migration.md states the review is a human convention (\"until a human reviews and reshapes them\"), not a CLI gate."
  );

  // bad_activation_without_review. Measured, not guessed: `--write` lands
  // migrated.uncategorized.auth-1 with `lifecycle: active` immediately, no
  // review step in between, and `uc matrix validate --repo .` afterwards
  // returns ok:true/complete:true with zero diagnostics. So this scenario's
  // claim — "migrated rows stay draft or planned until a human has reviewed
  // the feature printout" — is false for any row whose legacy scenario and
  // expected text happen to be complete.
  test.todo(
    "bad_activation_without_review — FALSE per the binary: a structurally-complete legacy row (scenario + expected present) is written with lifecycle: active on the very first --write, no human review step exists, and `uc matrix validate` accepts it clean. Migrated rows do NOT universally stay draft/planned pending review."
  );

  // edge_structurally_unusable_rows_stay_draft. Half of this is true and
  // measured: AUTH-2 (no expected outcome) and AUTH-3 (no scenario, no
  // steps) are always drafted with `lifecycle: planned`, never active — see
  // the `bad_import_is_never_silently_active` test.todo above for the
  // measurement. But the scenario requires BOTH "reviewed AND structurally
  // usable" before activation, and there is no "reviewed" gate at all: a
  // structurally usable row (AUTH-1) activates with zero review. Asserting
  // only the structural half would misrepresent this scenario as proven when
  // the row's actual claim — a review gate — does not exist.
  test.todo(
    "edge_structurally_unusable_rows_stay_draft — only half true per the binary: structurally incomplete rows (missing scenario/steps or expected outcome) are always drafted lifecycle: planned, but there is no 'reviewed' condition at all — a structurally complete row activates with zero human review, so the row's 'reviewed AND structurally usable' gate does not exist as stated."
  );
});
