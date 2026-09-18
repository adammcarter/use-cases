// The black-box oracle for three remaining rows of matrix/product.yml:
// product_inventory, sharded_human_readable_files and status_summary.
//
// matrix-product.test.ts already covers coverage_by_value_and_journey and
// integrity_degraded_nonfatal. claim_guardrails is parked pending an owner
// decision and is deliberately left untouched here too.
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

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-matrix-product-inventory-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  return { dir, env };
}

interface RowSpec {
  id: string;
  value: string;
  journey: string;
  tags: string[];
}

function rowYaml(row: RowSpec): string {
  return `  - id: ${row.id}
    title: Row ${row.id}
    lifecycle: active
    value_tier: ${row.value}
    journey_role: ${row.journey}
    usage_frequency: common
    tags: [${row.tags.join(", ")}]
    actor: agent
    intent: Exist so the query has something to select.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: ${row.id}.golden_runs
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

/** Write one feature shard: one feature summary, one or more rows. */
function writeShard(workspace: Workspace, fileName: string, featureId: string, rows: RowSpec[]): void {
  writeFileSync(
    join(workspace.dir, "use-cases", fileName),
    `schema_version: 1\nfeature:\n  id: ${featureId}\n  name: ${featureId}\n  summary: Summary for ${featureId}.\nuse_cases:\n${rows.map(rowYaml).join("")}`
  );
}

function addDamagedShard(workspace: Workspace, fileName = "broken.yml"): void {
  writeFileSync(join(workspace.dir, "use-cases", fileName), `schema_version: 1\nfeature:\n  id: probe.broken\n`);
}

interface ListRow {
  id: string;
  feature_id: string;
  source_path: string;
  value_tier: string;
  journey_role: string;
}
interface ListData {
  use_cases: ListRow[];
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

interface StatusData {
  matrix: ValidateData & { complete: boolean };
  evidence: {
    integrity: { state: string };
    counts: Record<string, number>;
  };
}

function status(workspace: Workspace) {
  return runUcJson<StatusData>(["matrix", "status", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

describe("matrix.product.product_inventory", () => {
  // golden_cli. A product-tier row and a primitive/support-tier row coexist in
  // one list, and each carries the value/journey metadata a selection is made
  // on.
  //
  // MEASURED GAP: the row also claims each row carries "usage and scenario
  // data". `matrix list --json` does not project usage_frequency or scenarios
  // at all — a row there is {id, title, feature_id, lifecycle, value_tier,
  // journey_role, source_path, semantic_hash, host_surfaces, tags}. That part
  // of the row is not something this CLI surface can prove; see the
  // test.todo below instead of a test that pretends it does.
  test("product-level and primitive support rows are listed together, each carrying value and journey data", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "product.yml", "probe.product", [
      { id: "probe.product.behavior", value: "critical", journey: "golden", tags: ["product-behavior"] }
    ]);
    writeShard(workspace, "primitive.yml", "probe.primitive", [
      { id: "probe.primitive.op", value: "supporting", journey: "golden", tags: ["primitive"] }
    ]);

    const { envelope } = list(workspace);
    expect(envelope.ok).toBe(true);
    const ids = envelope.data.use_cases.map((r) => r.id);
    expect(ids, "the product row and the primitive row are both addressable").toEqual(
      expect.arrayContaining(["probe.product.behavior", "probe.primitive.op"])
    );

    for (const row of envelope.data.use_cases) {
      expect(row.value_tier, `${row.id} carries a value tier`).toBeTruthy();
      expect(row.journey_role, `${row.id} carries a journey role`).toBeTruthy();
    }

    // Selectable by id alone: the id string is all that was needed above, no
    // implementation file was read to find these rows.
    const product = envelope.data.use_cases.find((r) => r.id === "probe.product.behavior");
    expect(product?.value_tier).toBe("critical");
  });

  test.todo(
    "golden_cli — the row also claims each row carries usage and scenario data, but " +
      "`matrix list --json` never projects usage_frequency or scenarios (measured); no CLI " +
      "surface exposes them per row, so this part is not provable black-box"
  );

  // edge_primitive_rows_stay_supporting. There is no schema field that marks a
  // row "primitive" vs "product" — the distinction lives in value_tier. A
  // supporting-tier row stays addressable on its own, but a critical+golden
  // cut leaves it out, which is what "supporting proof rather than the whole
  // product map" means in practice.
  test("a supporting-tier row stays addressable without appearing in the critical/golden cut", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "product.yml", "probe.product", [
      { id: "probe.product.behavior", value: "critical", journey: "golden", tags: ["product-behavior"] }
    ]);
    writeShard(workspace, "primitive.yml", "probe.primitive", [
      { id: "probe.primitive.op", value: "supporting", journey: "golden", tags: ["primitive"] }
    ]);

    const critical = list(workspace, ["--value", "critical"]).envelope.data.use_cases.map((r) => r.id);
    expect(critical).toEqual(["probe.product.behavior"]);
    expect(critical, "the primitive row does not crowd the headline cut").not.toContain("probe.primitive.op");

    const supporting = list(workspace, ["--value", "supporting"]).envelope.data.use_cases.map((r) => r.id);
    expect(supporting, "but it is still directly retrievable as supporting proof").toEqual(["probe.primitive.op"]);
  });
});

describe("matrix.product.sharded_human_readable_files", () => {
  // golden_layout. Two feature shards, each with one feature summary and one
  // related row, validate together as a single matrix.
  test("two feature shards validate together as one matrix", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [{ id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] }]);
    writeShard(workspace, "beta.yml", "probe.beta", [{ id: "probe.beta.two", value: "supporting", journey: "edge", tags: ["probe"] }]);

    const { envelope } = validate(workspace);
    expect(envelope.ok).toBe(true);
    expect(envelope.data.valid).toBe(true);
    expect(envelope.data.files.map((f) => f.path).sort()).toEqual(["use-cases/alpha.yml", "use-cases/beta.yml"]);
    expect(envelope.data.files.every((f) => f.status === "loaded")).toBe(true);
    expect(envelope.data.counts.files_loaded).toBe(2);
  });

  // bad_damaged_shard_is_named. Damaging one shard leaves the other loadable,
  // and validation names the damaged file rather than reporting a bare
  // failure.
  test("a damaged shard is named in the per-file report while its sibling still loads", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [{ id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] }]);
    addDamagedShard(workspace);

    const { envelope } = validate(workspace);
    expect(envelope.ok).toBe(false);
    expect(envelope.data.valid).toBe(false);
    const damaged = envelope.data.files.filter((f) => f.status !== "loaded");
    expect(damaged.map((f) => f.path)).toEqual(["use-cases/broken.yml"]);
    expect(envelope.data.files.find((f) => f.path === "use-cases/alpha.yml")?.status).toBe("loaded");
  });

  // edge_one_feature_summary_per_file. Every row loaded from a given shard
  // reports that shard's own feature id, and no row crosses over to another
  // shard's feature id — one feature per file, observed through the rows it
  // produces.
  test("rows loaded from one shard all share that shard's single feature id", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [
      { id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] },
      { id: "probe.alpha.two", value: "core", journey: "edge", tags: ["probe"] }
    ]);
    writeShard(workspace, "beta.yml", "probe.beta", [{ id: "probe.beta.one", value: "supporting", journey: "golden", tags: ["probe"] }]);

    const { envelope } = list(workspace);
    const byFile = new Map<string, Set<string>>();
    for (const row of envelope.data.use_cases) {
      const features = byFile.get(row.source_path) ?? new Set<string>();
      features.add(row.feature_id);
      byFile.set(row.source_path, features);
    }
    expect(byFile.get("use-cases/alpha.yml")).toEqual(new Set(["probe.alpha"]));
    expect(byFile.get("use-cases/beta.yml")).toEqual(new Set(["probe.beta"]));
  });
});

describe("matrix.product.status_summary", () => {
  // golden_report. Row counts, integrity state, and evidence coverage are all
  // readable from the one `matrix status` call.
  test("matrix and evidence health are both readable from one command", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [{ id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] }]);

    const { envelope } = status(workspace);
    expect(envelope.ok).toBe(true);
    expect(envelope.data.matrix.counts.use_case_candidates).toBe(1);
    expect(envelope.data.matrix.integrity.state).toBe("clean");
    expect(envelope.data.evidence.integrity.state).toBe("clean");
    expect(envelope.data.evidence.counts).toBeTruthy();
  });

  // bad_summary_is_never_a_cached_claim. Editing a use-case file and
  // immediately re-running status (no other command in between) must change
  // the reported counts — a stale number would mean the summary is cached
  // rather than derived from the files on disk.
  test("editing a shard and re-running status immediately changes the reported counts", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [{ id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] }]);

    const before = status(workspace).envelope.data.matrix.counts.use_case_candidates;
    expect(before).toBe(1);

    writeShard(workspace, "alpha.yml", "probe.alpha", [
      { id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] },
      { id: "probe.alpha.two", value: "core", journey: "edge", tags: ["probe"] }
    ]);

    const after = status(workspace).envelope.data.matrix.counts.use_case_candidates;
    expect(after, "the same file, changed on disk, is not answered from a cache").toBe(2);
  });

  // edge_gaps_visible_without_a_full_plan_run. A damaged shard's integrity
  // gap shows up straight from `matrix status` — no `plan showcase` or
  // `plan walkthrough` needed to see it.
  test("an integrity gap is visible from status alone, without running a plan", () => {
    const workspace = makeWorkspace();
    writeShard(workspace, "alpha.yml", "probe.alpha", [{ id: "probe.alpha.one", value: "core", journey: "golden", tags: ["probe"] }]);
    addDamagedShard(workspace);

    const { envelope } = status(workspace);
    expect(envelope.ok).toBe(false);
    expect(envelope.data.matrix.complete).toBe(false);
    expect(envelope.data.matrix.integrity.state).toBe("partial");
    expect(envelope.data.matrix.integrity.blocking_diagnostic_count).toBeGreaterThan(0);
  });
});
