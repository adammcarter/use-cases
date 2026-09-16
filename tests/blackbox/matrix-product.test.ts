// The black-box oracle for the two white-box rows of matrix/product.yml.
//
// The file's other rows are left alone: product_inventory,
// sharded_human_readable_files and status_summary have no runnable verifier and
// belong to the 34 that need one, and claim_guardrails is one of the eight
// doctrine rows parked for the end.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

function rowYaml({ name, value, journey }: RowSpec): string {
  return `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: ${value}
    journey_role: ${journey}
    usage_frequency: common
    tags: [probe]
    actor: agent
    intent: Exist so the query has something to select.
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
      mode: none
    approval_policy:
      mode: none
`;
}

// A spread across both axes the row selects on.
const ROWS: RowSpec[] = [
  { name: "crit_golden", value: "critical", journey: "golden" },
  { name: "core_edge", value: "core", journey: "edge" },
  { name: "supp_negative", value: "supporting", journey: "negative" },
  { name: "core_failure", value: "core", journey: "failure" }
];

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-matrix-product-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(
    join(dir, "use-cases", "probe.yml"),
    `schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n${ROWS.map(rowYaml).join("")}`
  );
  return { dir, env };
}

/** Damage a SECOND shard, leaving the first intact. */
function addDamagedShard(workspace: Workspace): void {
  writeFileSync(join(workspace.dir, "use-cases", "broken.yml"), "schema_version: 1\nfeature:\n  id: probe.broken\n");
}

interface ListData {
  use_cases: Array<{ id: string; value_tier: string; journey_role: string }>;
}

function list(workspace: Workspace, args: string[] = []) {
  return runUcJson<ListData>(["matrix", "list", "--repo", ".", ...args], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

interface ValidateData {
  valid: boolean;
  integrity: { state: string; populated: boolean; blocking_diagnostic_count: number };
  counts: Record<string, number>;
  files: Array<{ path: string; status: string }>;
}

function validate(workspace: Workspace) {
  return runUcJson<ValidateData>(["matrix", "validate", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

//: @use-case:matrix.product.coverage_by_value_and_journey#blackbox
describe("matrix.product.coverage_by_value_and_journey", () => {
  // golden_selection. High-value rows separate cleanly from the long tail,
  // which is what makes a short showcase selectable at all.
  test("filtering by value tier and journey role returns sound, non-empty slices", () => {
    const workspace = makeWorkspace();

    const critical = list(workspace, ["--value", "critical"]);
    expect(critical.envelope.ok).toBe(true);
    expect(critical.envelope.data.use_cases.length).toBeGreaterThan(0);
    for (const row of critical.envelope.data.use_cases) {
      expect(row.value_tier, "a filtered slice contains only what was asked for").toBe("critical");
    }

    const golden = list(workspace, ["--journey-role", "golden"]);
    expect(golden.envelope.data.use_cases.length).toBeGreaterThan(0);
    for (const row of golden.envelope.data.use_cases) {
      expect(row.journey_role).toBe("golden");
    }
  });

  // edge_deeper_cuts_reach_beyond_golden. A walkthrough needs the alternate,
  // edge, negative and failure rows a showcase would leave out — and the two
  // cuts must genuinely differ, or the distinction is decorative.
  test("a deeper cut reaches the edge, negative and failure rows a golden cut omits", () => {
    const workspace = makeWorkspace();

    const all = list(workspace).envelope.data.use_cases.map((r) => r.id);
    const goldenOnly = list(workspace, ["--journey-role", "golden"]).envelope.data.use_cases.map((r) => r.id);

    for (const role of ["edge", "negative", "failure"]) {
      const slice = list(workspace, ["--journey-role", role]).envelope.data.use_cases;
      expect(slice.length, `${role} rows must be selectable`).toBeGreaterThan(0);
      for (const row of slice) {
        expect(goldenOnly, `${row.id} is ${role}, so a golden cut must not contain it`).not.toContain(row.id);
      }
    }
    expect(goldenOnly.length, "the golden cut is narrower than the whole matrix").toBeLessThan(all.length);
  });
});
//: @use-case:end matrix.product.coverage_by_value_and_journey#blackbox

//: @use-case:matrix.product.integrity_degraded_nonfatal#blackbox
describe("matrix.product.integrity_degraded_nonfatal", () => {
  // golden_partial. Damaged YAML must not bring the system down: the valid
  // rows stay addressable.
  test("a damaged shard keeps its valid siblings addressable", () => {
    const workspace = makeWorkspace();
    const before = list(workspace).envelope.data.use_cases.length;
    expect(before).toBe(ROWS.length);

    addDamagedShard(workspace);

    const after = list(workspace);
    expect(
      after.envelope.data.use_cases.length,
      "valid rows survive a damaged neighbour"
    ).toBe(before);
  });

  // bad_damage_is_surfaced_not_swallowed. Tolerating damage is never hiding it,
  // and the damaged FILE is named rather than left to be hunted.
  test("integrity goes partial and the damaged file is named", () => {
    const workspace = makeWorkspace();
    expect(validate(workspace).envelope.data.integrity.state).toBe("clean");

    addDamagedShard(workspace);
    const { envelope } = validate(workspace);

    expect(envelope.ok).toBe(false);
    expect(envelope.data.valid).toBe(false);
    // `partial` is the distinction this row exists for. An EMPTY matrix reports
    // `unusable` instead — degraded and unusable are not the same state.
    expect(envelope.data.integrity.state).toBe("partial");
    expect(envelope.data.integrity.populated, "partial still means populated").toBe(true);

    const damaged = envelope.data.files.filter((f) => f.status !== "loaded");
    expect(damaged.map((f) => f.path.split("/").pop())).toContain("broken.yml");
    expect(envelope.data.files.some((f) => f.status === "loaded"), "the good shard still loads").toBe(true);
  });

  // edge_partial_integrity_precedes_any_claim. The state is reported before
  // anything downstream could read the rows as complete coverage.
  test("the partial state is visible in the same result that still carries the rows", () => {
    const workspace = makeWorkspace();
    addDamagedShard(workspace);

    const { envelope } = validate(workspace);
    expect(envelope.data.counts.files_loaded).toBeGreaterThan(0);
    expect(envelope.data.counts.files_excluded).toBeGreaterThan(0);
    expect(
      envelope.data.integrity.blocking_diagnostic_count,
      "the damage is counted, not merely mentioned"
    ).toBeGreaterThan(0);
  });
});
//: @use-case:end matrix.product.integrity_degraded_nonfatal#blackbox
