// The black-box oracle for evidence/core.yml.
//
// One row, and until now its whole scenario body was a single line: "Run
// evidence record." What the row actually promises is narrower and more
// interesting — proof is persisted as append-only history and NOTHING else is
// created alongside it, because a summary file would become a second source of
// truth that nobody replays.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
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

const MATRIX = `schema_version: 1
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
    intent: Exist so evidence can be recorded against it.
    preconditions: [Nothing.]
    trigger: An agent records evidence.
    scenarios:
      - id: probe.core.alpha.golden_runs
        kind: steps
        steps: [Record it.]
        observable_outcomes: [An event is appended.]
    observable_outcomes: [A JSONL event is appended under evidence.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-evidence-core-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), MATRIX);
  return { dir, env };
}

function record(workspace: Workspace, useCase: string, key: string) {
  return runUcJson<{ appended: boolean; ledger_path: string; durability: string }>(
    ["evidence", "record", "--repo", ".", "--use-case", useCase,
      "--summary", "the behaviour was observed", "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

/** Every file under evidence/, recursively, relative to the workspace. */
function evidenceFiles(workspace: Workspace): string[] {
  const root = join(workspace.dir, "evidence");
  const found: string[] = [];
  const walk = (dir: string, prefix: string): void => {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) walk(full, `${prefix}${entry}/`);
      else found.push(`${prefix}${entry}`);
    }
  };
  walk(root, "");
  return found;
}

describe("evidence.core.record", () => {
  // golden_cli.
  test("recording evidence appends one JSONL event under evidence/", () => {
    const workspace = makeWorkspace();
    const { envelope } = record(workspace, "probe.core.alpha", "first");

    expect(envelope.ok).toBe(true);
    expect(envelope.data.appended).toBe(true);
    expect(envelope.data.ledger_path).toMatch(/^evidence\/.*\.jsonl$/);

    const stored = readFileSync(join(workspace.dir, envelope.data.ledger_path), "utf8").trim();
    expect(stored.split("\n"), "one event, one line").toHaveLength(1);
    expect(JSON.parse(stored)).toMatchObject({ event_type: "evidence_recorded" });
  });

  // bad_unresolvable_use_case. A dangling target is refused rather than
  // recorded and left for someone to trip over later.
  test("evidence naming a use case that does not resolve is refused and appends nothing", () => {
    const workspace = makeWorkspace();
    record(workspace, "probe.core.alpha", "first");
    const before = evidenceFiles(workspace);

    const { envelope } = record(workspace, "probe.core.ghost", "ghost");
    expect(envelope.ok).toBe(false);
    expect(JSON.stringify(envelope.diagnostics)).toContain("evidence.use_case.unresolved");
    expect(evidenceFiles(workspace), "a refused record writes nothing").toEqual(before);
  });

  // edge_no_summary_state_is_created. The events ARE the state. A summary or
  // index file beside them would be a second source of truth that no replay
  // reads, and it would drift the moment anything was corrected.
  test("recording creates no summary or index beside the append-only history", () => {
    const workspace = makeWorkspace();
    record(workspace, "probe.core.alpha", "first");
    record(workspace, "probe.core.alpha", "second");

    const files = evidenceFiles(workspace);
    expect(files.length).toBeGreaterThan(0);
    expect(
      files.filter((f) => !f.endsWith(".jsonl")),
      `only append-only ledgers may exist, found: ${files.join(", ")}`
    ).toEqual([]);
  });
});
