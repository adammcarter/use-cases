// The black-box oracle for matrix/core.yml.
//
// These two rows are among the eight that carry `verification_policy: mode:
// none` — no verifier at all, so `use-cases verify` has never had anything to run for
// them. Converting them adds a verifier where none existed, which is the bulk
// of what ladder row 2 still has to do.
//
// Self-contained on purpose: a shared oracle file means one edit stales every
// row bound to it.
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

// A COMPLETE matrix. Mutation is refused outright against an incomplete one
// (`matrix.mutation_incomplete_matrix`), so a seed row has to be here first or
// every test below would measure that refusal instead of the behaviour.
const SEED_MATRIX = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.seed
    title: Seed row
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so the matrix is complete enough to mutate.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: probe.core.seed.golden_runs
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

const NEW_ROW = JSON.stringify({
  id: "probe.core.alpha",
  title: "Alpha",
  lifecycle: "planned",
  value_tier: "core",
  journey_role: "golden",
  usage_frequency: "common"
});

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-matrix-core-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), SEED_MATRIX);
  return { dir, env };
}

function uc(workspace: Workspace, args: string[]) {
  const [command, sub, ...rest] = args;
  return runUcJson([command, sub, "--repo", ".", ...rest], { cwd: workspace.dir, env: workspace.env });
}

interface MutationData {
  status: string;
  use_case_id: string | null;
  before_hash: string | null;
  after_hash: string | null;
  diagnostics: Array<{ code: string }>;
}

function featureFile(workspace: Workspace): string {
  return readFileSync(join(workspace.dir, "use-cases", "probe.yml"), "utf8");
}

function rowCount(workspace: Workspace): number {
  return featureFile(workspace).split("\n").filter((l) => /^ {2}- id: /.test(l)).length;
}

describe("matrix.core.validate", () => {
  // golden_cli.
  test("a clean workspace reports clean integrity", () => {
    const workspace = makeWorkspace();
    const { envelope } = uc(workspace, ["matrix", "validate"]);
    const data = envelope.data as { valid: boolean; integrity: { state: string } };

    expect(data.valid).toBe(true);
    expect(data.integrity.state).toBe("clean");
    expect(envelope.diagnostics).toHaveLength(0);
  });

  // bad_a_damaged_matrix_is_never_clean. Tolerating damage elsewhere is a
  // separate behaviour; what must never happen is damage reading as health.
  test("a damaged file is never reported as clean, and the diagnostics say what is wrong", () => {
    const workspace = makeWorkspace();
    writeFileSync(join(workspace.dir, "use-cases", "broken.yml"), "schema_version: 1\nfeature:\n  id: probe.core\n");

    const { envelope } = uc(workspace, ["matrix", "validate"]);
    const data = envelope.data as { valid: boolean; integrity: { state: string } };

    expect(data.valid).toBe(false);
    expect(data.integrity.state).not.toBe("clean");
    expect(envelope.diagnostics.length, "the damage must be named").toBeGreaterThan(0);
  });
});

describe("matrix.core.mutate", () => {
  // golden_upsert. A mutation returns before and after hashes so a caller can
  // see exactly what moved, and the matrix stays clean afterwards.
  test("upsert adds a row, returns before and after hashes, and leaves the matrix clean", () => {
    const workspace = makeWorkspace();
    const before = rowCount(workspace);

    const { envelope } = uc(workspace, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", NEW_ROW]);
    const data = envelope.data as unknown as MutationData;

    expect(envelope.ok).toBe(true);
    expect(data.status).toBe("created");
    expect(data.use_case_id).toBe("probe.core.alpha");
    expect(data.after_hash, "an accepted write reports the hash it produced").toMatch(/^sha256:/);
    expect(rowCount(workspace)).toBe(before + 1);

    const validated = uc(workspace, ["matrix", "validate"]).envelope.data as { valid: boolean };
    expect(validated.valid, "the matrix stays structurally clean after an accepted write").toBe(true);
  });

  // edge_upsert_lands_on_an_existing_row. Upsert means both; landing on an id
  // that exists updates it rather than adding a second copy.
  test("upsert on an existing id updates it in place rather than duplicating", () => {
    const workspace = makeWorkspace();
    uc(workspace, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", NEW_ROW]);
    const afterFirst = rowCount(workspace);

    const retitled = JSON.stringify({ ...JSON.parse(NEW_ROW), title: "Alpha retitled" });
    const { envelope } = uc(workspace, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", retitled]);
    const data = envelope.data as unknown as MutationData;

    expect(data.status).toBe("updated");
    expect(data.before_hash).not.toBe(data.after_hash);
    expect(rowCount(workspace), "no duplicate row").toBe(afterFirst);
    expect(featureFile(workspace)).toContain("Alpha retitled");
  });

  // golden_remove. Removal is a lifecycle transition, not a deletion: the
  // history of the row survives it.
  test("remove is a soft lifecycle transition that preserves the row", () => {
    const workspace = makeWorkspace();
    uc(workspace, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", NEW_ROW]);
    const before = rowCount(workspace);

    const { envelope } = uc(workspace, ["matrix", "remove", "--use-case", "probe.core.alpha", "--reason", "retired"]);
    const data = envelope.data as unknown as MutationData;

    expect(envelope.ok).toBe(true);
    expect(data.status).toBe("removed");
    expect(rowCount(workspace), "the row is not physically deleted").toBe(before);
    expect(featureFile(workspace)).toContain("lifecycle: removed");
  });

  // bad_stale_expected_hash. A write cannot land on a matrix that moved
  // underneath it.
  test("a stale --expected-hash blocks the write", () => {
    const workspace = makeWorkspace();
    // The guard is documented as being FOR UPDATES: creating a row has no prior
    // hash to guard, so the flag is ignored there. The row has to exist first
    // or this measures a create, not a concurrency guard.
    uc(workspace, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", NEW_ROW]);
    const fileBefore = featureFile(workspace);

    const retitled = JSON.stringify({ ...JSON.parse(NEW_ROW), title: "Alpha from a stale reader" });
    const { envelope } = uc(workspace, [
      "matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", retitled,
      "--expected-hash", "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    ]);
    const data = envelope.data as unknown as MutationData;

    expect(envelope.ok).toBe(false);
    expect(data.status).toBe("blocked");
    expect(data.diagnostics.map((d) => d.code)).toContain("matrix.mutation_hash_mismatch");
    expect(featureFile(workspace), "a blocked write changes nothing").toBe(fileBefore);
  });

  // bad_path_escape_or_damaged_matrix. Two ways a write must be refused, kept
  // in one scenario because both are "the target is not somewhere we may write".
  test("a path escape is blocked, and so is any mutation of an incomplete matrix", () => {
    const workspace = makeWorkspace();
    const escape = uc(workspace, ["matrix", "upsert", "--file", "../outside.yml", "--use-case-json", NEW_ROW]);
    const escapeData = escape.envelope.data as unknown as MutationData;
    expect(escape.envelope.ok).toBe(false);
    expect(escapeData.status).toBe("blocked");
    expect(escapeData.diagnostics.map((d) => d.code)).toContain("matrix.mutation_path_escape");

    // An incomplete matrix refuses mutation outright, so a damaged workspace
    // cannot be edited further into a worse state.
    const damaged = makeWorkspace();
    writeFileSync(join(damaged.dir, "use-cases", "probe.yml"), "schema_version: 1\nfeature:\n  id: probe.core\n");
    const blocked = uc(damaged, ["matrix", "upsert", "--file", "use-cases/probe.yml", "--use-case-json", NEW_ROW]);
    expect(blocked.envelope.ok).toBe(false);
    expect((blocked.envelope.data as unknown as MutationData).status).toBe("blocked");
  });
});
