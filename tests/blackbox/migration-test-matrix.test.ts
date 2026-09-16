// The black-box oracle for migration/test-matrix.yml.
//
// Its whole scenario body used to be one line: "Run migrate test-matrix in
// dry-run or write mode." What the row actually promises is a trust boundary —
// a legacy "PASS" column must not become evidence, and nothing may arrive
// active. Both are asserted here against generated files on disk.
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

// A legacy matrix carrying exactly what must NOT become proof: status columns
// reading PASS, DONE and accepted.
const LEGACY = `# Test matrix

| ID | Behaviour | Status | Owner |
|----|-----------|--------|-------|
| AUTH-1 | User signs in with valid credentials | PASS | alice |
| AUTH-2 | Sign-in rejects a bad password | DONE | bob |
| AUTH-3 | Session survives a refresh | accepted | carol |
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-migration-"));
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
  summary: Record<string, number>;
  would_write: Array<{ path: string; action: string }>;
  warnings: Array<{ code: string; message: string }>;
  drafts: Array<{ output_path: string; use_case_ids: string[]; content: string }>;
}

function migrate(workspace: Workspace, extra: string[]) {
  return runUcJson<MigrationData>(
    ["migrate", "test-matrix", "--repo", ".", "--source", "TEST-MATRIX.md", "--out", "use-cases/_migrated", ...extra],
    { cwd: workspace.dir, env: workspace.env }
  );
}

function migratedFiles(workspace: Workspace): string[] {
  try {
    return readdirSync(join(workspace.dir, "use-cases", "_migrated"));
  } catch {
    return [];
  }
}

//: @use-case:migration.test_matrix.draft#blackbox
describe("migration.test_matrix.draft", () => {
  // golden_dry_run. Dry run is the DEFAULT, and it writes nothing — the preview
  // has to be safe to run against someone's real repo.
  test("a dry run reports what it would do and writes nothing", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    expect(envelope.ok).toBe(true);
    expect(envelope.data.mode).toBe("dry_run");
    expect(envelope.data.summary.rows_seen).toBe(3);
    expect(envelope.data.summary.files_written).toBe(0);
    expect(envelope.data.would_write.length).toBeGreaterThan(0);
    expect(migratedFiles(workspace), "a preview must leave the disk alone").toEqual([]);
  });

  // bad_old_status_is_not_proof. The trust boundary: a legacy PASS is carried
  // as review context and warned about, never turned into evidence.
  test("legacy status marks are warned about and never become evidence", () => {
    const workspace = makeWorkspace();
    const { envelope } = migrate(workspace, ["--dry-run"]);

    const codes = envelope.data.warnings.map((w) => w.code);
    expect(codes, "each legacy status must be called out").toContain("old_status_not_evidence");
    expect(envelope.data.summary.rows_needing_review).toBe(3);

    // Nothing arrives active, and no evidence id is minted for any row.
    const draft = envelope.data.drafts[0].content;
    expect(draft).not.toContain("lifecycle: active");
    expect(draft, "drafts carry no evidence ids").not.toMatch(/evidence_id/);
    expect(draft, "the file says outright what it is").toContain("Draft intended behavior only");
  });

  // edge_write_mode_writes_the_drafts. The preview is only worth having if what
  // lands matches it.
  test("write mode writes exactly what the dry run planned, all of it planned lifecycle", () => {
    const workspace = makeWorkspace();
    const planned = migrate(workspace, ["--dry-run"]).envelope.data;

    const { envelope } = migrate(workspace, ["--write"]);
    expect(envelope.ok).toBe(true);
    expect(envelope.data.mode).toBe("write");
    expect(envelope.data.summary.files_written).toBe(planned.summary.files_planned);

    // Every planned draft landed, by name.
    const written = migratedFiles(workspace);
    for (const entry of planned.would_write) {
      expect(written, `${entry.path} was planned and must land`).toContain(entry.path.split("/").pop());
    }

    // Alongside them the writer leaves a migration receipt. It is not a draft —
    // files_written counts drafts only — and it is what makes the output
    // auditable against its source afterwards.
    expect(written, "the run leaves a receipt beside the drafts").toContain(".use-cases-migration.json");

    const drafts = written.filter((name) => name.endsWith(".yml"));
    expect(drafts.length).toBe(planned.summary.files_planned);

    const contents = drafts
      .map((name) => readFileSync(join(workspace.dir, "use-cases", "_migrated", name), "utf8"))
      .join("\n");
    expect(contents).toContain("lifecycle: planned");
    expect(contents, "migration never grants acceptance").not.toContain("lifecycle: active");
  });
});
//: @use-case:end migration.test_matrix.draft#blackbox
