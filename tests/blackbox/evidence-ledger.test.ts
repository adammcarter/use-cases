// The black-box oracle for the four white-box rows of evidence/ledger.yml.
//
// The file's other two rows are already oracle rows and are left alone:
// crash_durable_ledger_writes is driven by a test that imports no internals,
// and untrusted_content_boundary is one of the eight doctrine rows parked for
// the end.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, appendFileSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

function matrix(rows: string[]): string {
  const body = rows
    .map(
      (name) => `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so evidence can be recorded against it.
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
`
    )
    .join("");
  return `schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n${body}`;
}

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(rows = ["alpha"]): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-evidence-ledger-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), matrix(rows));
  return { dir, env };
}

interface RecordData {
  appended: boolean;
  ledger_path: string;
  event: { event_id: string; aggregate_id: string };
}

function record(workspace: Workspace, row: string, key: string, summary = "observed") {
  return runUcJson<RecordData>(
    ["evidence", "record", "--repo", ".", "--use-case", `probe.core.${row}`,
      "--summary", summary, "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

interface StatusData {
  integrity: { state: string; unknown_scope_damage: boolean };
  aggregates: Array<{
    assurance: { class: string; capture_method: string };
    /** The row hashes this evidence was taken AGAINST. Comparing them with the
     *  row's current hash is what makes stale evidence visible. */
    freshness_inputs: { use_case_semantic_hashes: string[]; explicit_invalidation: boolean };
    target_links: Array<{ use_case_id: string; use_case_semantic_hash: string }>;
    status: string;
  }>;
}

/** The row's semantic hash as the matrix currently reports it. */
function currentRowHash(workspace: Workspace, row: string): string {
  const { envelope } = runUcJson<{ use_cases: Array<{ id: string; semantic_hash: string }> }>(
    ["matrix", "list", "--repo", "."],
    { cwd: workspace.dir, env: workspace.env }
  );
  const found = envelope.data.use_cases.find((r) => r.id === `probe.core.${row}`);
  expect(found, `probe.core.${row} must be listed`).toBeTruthy();
  return found!.semantic_hash;
}

function status(workspace: Workspace) {
  return runUcJson<StatusData>(["evidence", "status", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

describe("evidence.ledger.product_proof_map", () => {
  // golden_record. Proof is traceable from the event back to the row and the
  // hash of the row as it was when the evidence was taken.
  test("evidence links to its use case and to the row's semantic hash", () => {
    const workspace = makeWorkspace();
    const appended = record(workspace, "alpha", "first");
    expect(appended.envelope.ok).toBe(true);

    const stored = JSON.parse(
      readFileSync(join(workspace.dir, appended.envelope.data.ledger_path), "utf8").trim()
    ) as { payload: { targets: Array<{ use_case_id: string; use_case_semantic_hash: string }> } };

    expect(stored.payload.targets[0].use_case_id).toBe("probe.core.alpha");
    expect(stored.payload.targets[0].use_case_semantic_hash).toMatch(/^sha256:/);
  });

  // bad_hash_mismatch. A row that changed after its evidence was taken does not
  // keep the old proof.
  test("evidence whose row hash no longer matches the row is detectably stale", () => {
    const workspace = makeWorkspace();
    record(workspace, "alpha", "first");

    // While nothing has changed, the hash the evidence was taken against IS the
    // row's current hash.
    const recorded = status(workspace).envelope.data.aggregates[0].target_links[0].use_case_semantic_hash;
    expect(recorded).toBe(currentRowHash(workspace, "alpha"));

    const path = join(workspace.dir, "use-cases", "probe.yml");
    writeFileSync(path, readFileSync(path, "utf8").replace("title: Row alpha", "title: Row alpha, retitled"));

    // After the edit the row moves and the evidence does not, which is what
    // makes the mismatch detectable rather than silent.
    const stillRecorded = status(workspace).envelope.data.aggregates[0].target_links[0].use_case_semantic_hash;
    expect(stillRecorded, "the evidence keeps the hash it was taken against").toBe(recorded);
    expect(
      currentRowHash(workspace, "alpha"),
      "a changed row must no longer match the hash its evidence carries"
    ).not.toBe(recorded);
  });

  // bad_missing_row. A dangling link is reported, not silently dropped.
  test("evidence naming a row that has left the matrix is reported", () => {
    const workspace = makeWorkspace(["alpha", "beta"]);
    record(workspace, "beta", "first");

    const path = join(workspace.dir, "use-cases", "probe.yml");
    const text = readFileSync(path, "utf8");
    writeFileSync(path, text.slice(0, text.indexOf("  - id: probe.core.beta")));

    const { envelope } = status(workspace);
    expect(
      JSON.stringify(envelope.data) + JSON.stringify(envelope.diagnostics),
      "the dangling target must surface somewhere"
    ).toContain("probe.core.beta");
  });
});

describe("evidence.ledger.append_only_corrections", () => {
  // golden_void and edge_history_survives_the_correction.
  test("a void is appended with the correct head, and the original event survives", () => {
    const workspace = makeWorkspace();
    const appended = record(workspace, "alpha", "first");
    const { event, ledger_path } = appended.envelope.data;
    const before = readFileSync(join(workspace.dir, ledger_path), "utf8");

    const voided = runUcJson(
      ["evidence", "void", "--repo", ".", "--evidence", event.aggregate_id,
        "--expected-head", event.event_id, "--reason", "recorded against the wrong row"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(voided.envelope.ok).toBe(true);

    const after = readFileSync(join(workspace.dir, ledger_path), "utf8");
    expect(after.startsWith(before), "the original event is never rewritten").toBe(true);
    expect(after.trim().split("\n").length, "the void is appended").toBeGreaterThan(
      before.trim().split("\n").length
    );
  });

  // bad_wrong_head_is_refused. A correction cannot be applied to a ledger that
  // moved underneath it.
  test("a void naming the wrong head is refused and writes nothing", () => {
    const workspace = makeWorkspace();
    const appended = record(workspace, "alpha", "first");
    const { event, ledger_path } = appended.envelope.data;
    const before = readFileSync(join(workspace.dir, ledger_path), "utf8");

    const voided = runUcJson(
      ["evidence", "void", "--repo", ".", "--evidence", event.aggregate_id,
        "--expected-head", "evt_not_the_head", "--reason", "stale reader"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(voided.envelope.ok).toBe(false);
    expect(readFileSync(join(workspace.dir, ledger_path), "utf8")).toBe(before);
  });
});

describe("evidence.ledger.assurance_and_freshness", () => {
  // golden_assurance_class. The class reflects how the proof was CAPTURED, not
  // what it claims: a written summary is `reported` whatever it says.
  test("a written summary is classed reported, however confident it reads", () => {
    const workspace = makeWorkspace();
    record(workspace, "alpha", "first", "I ran the whole suite and everything passed");

    const aggregate = status(workspace).envelope.data.aggregates[0];
    expect(aggregate.assurance.class).toBe("reported");
    expect(aggregate.assurance.capture_method).toBe("reported");
  });

  // bad_stale_is_not_reported_as_fresh and golden_freshness_keeps_states_distinct.
  test("the inputs freshness is judged from are recorded, and stop matching when the row moves", () => {
    const workspace = makeWorkspace();
    record(workspace, "alpha", "first");

    const inputs = status(workspace).envelope.data.aggregates[0].freshness_inputs;
    expect(inputs.explicit_invalidation).toBe(false);
    expect(inputs.use_case_semantic_hashes, "the hashes judged against are recorded, not inferred later")
      .toContain(currentRowHash(workspace, "alpha"));

    const path = join(workspace.dir, "use-cases", "probe.yml");
    writeFileSync(path, readFileSync(path, "utf8").replace("title: Row alpha", "title: Row alpha, moved on"));

    const after = status(workspace).envelope.data.aggregates[0].freshness_inputs;
    expect(after.use_case_semantic_hashes, "the recorded inputs do not move with the row").toEqual(
      inputs.use_case_semantic_hashes
    );
    expect(
      after.use_case_semantic_hashes,
      "so they no longer match the row, which is the staleness"
    ).not.toContain(currentRowHash(workspace, "alpha"));
  });
});

describe("evidence.ledger.damaged_ledger_replay", () => {
  // golden_partial. Valid events survive a damaged neighbour.
  test("a torn line does not cost the valid events around it", () => {
    const workspace = makeWorkspace();
    const first = record(workspace, "alpha", "first");
    record(workspace, "alpha", "second");
    expect(status(workspace).envelope.data.aggregates.length).toBe(2);

    appendFileSync(
      join(workspace.dir, first.envelope.data.ledger_path),
      '{"schema_version":1,"event_type":"evidence_recorded","BROKEN\n'
    );

    const { envelope } = status(workspace);
    expect(
      envelope.data.aggregates.length,
      "valid proof is not discarded because a neighbouring line is damaged"
    ).toBe(2);
  });

  // bad_damage_is_never_silently_clean. Tolerating damage is not hiding it.
  test("damage moves integrity off clean and is named in the diagnostics", () => {
    const workspace = makeWorkspace();
    const first = record(workspace, "alpha", "first");
    expect(status(workspace).envelope.data.integrity.state).toBe("clean");

    appendFileSync(
      join(workspace.dir, first.envelope.data.ledger_path),
      '{"schema_version":1,"event_type":"evidence_recorded","BROKEN\n'
    );

    const { envelope } = status(workspace);
    expect(envelope.ok).toBe(false);
    expect(envelope.data.integrity.state, "damage is partial, never clean").toBe("partial");
    expect(envelope.data.integrity.unknown_scope_damage).toBe(true);
    expect(JSON.stringify(envelope.diagnostics)).toContain("evidence_parse_error");
  });
});
