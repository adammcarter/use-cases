// The three hardest scenarios from the row 1b slice, proved through the binary.
//
// Row 1b deepened lifecycle/signals.yml from 19 scenarios to 52 and recorded a
// finding: all 12 rows are black-box reachable. That finding was READ off the
// white-box test names, which is not the same as proving a scenario can be
// expressed through the CLI. So the three least obviously expressible scenarios
// are written here, first, before the remaining 23 feature files are deepened on
// the strength of that claim:
//
//   local_results_are_attested.edge_scan_never_mints_a_key
//   performed_runs_count.edge_same_row_driven_twice
//   run_class_is_derived.bad_overclaimed_live_demo
//
// If one of these could not be written, it would be a bucket (c) — a behaviour
// needing a new CLI affordance to be observable — which under ADR 0007 decision
// 8 stops the ladder. Finding that on row 1 rather than row 4 is the point.
//
// Everything here talks ONLY to the binary: no core import, no internal call.
// Each test builds its workspace from scratch, so nothing depends on a fixture
// that a later change might reshape. UC_RUN_KEY_FILE is always pointed at a
// throwaway path, so no test reads or writes the developer's own machine key.
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
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

/** A verifier block, indented to sit under `verification_policy.verifiers`. */
const PASSING_SCRIPT = `        script:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", "exit 0"]
          inputs: ["src/thing.ts"]`;

function featureFile(verifierBlock: string, requiredKind = "test_result", verifierId = "script"): string {
  return `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: A behaviour that exists so a scenario can be proved through the CLI.
use_cases:
  - id: probe.core.thing
    title: The thing works
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Prove one scenario end to end through the binary.
    preconditions: [A source file exists.]
    trigger: An agent runs the loop.
    scenarios:
      - id: probe.core.thing.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It works.]
    observable_outcomes: [The row reaches a proven state.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
${verifierBlock}
      requirements:
        - evidence_kind: ${requiredKind}
          required_verifiers: [${verifierId}]
          minimum_count: 1
    approval_policy:
      mode: none
`;
}

interface Workspace {
  dir: string;
  env: Record<string, string>;
  runKeyPath: string;
}

/** A bound, ready-to-verify workspace, built only through the CLI. */
function makeWorkspace(
  verifierBlock: string = PASSING_SCRIPT,
  requiredKind = "test_result",
  verifierId = "script"
): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-"));
  tempDirs.push(dir);
  const runKeyPath = join(dir, "machine", "run-key");
  const env = { UC_RUN_KEY_FILE: runKeyPath };

  mkdirSync(join(dir, "use-cases"), { recursive: true });
  mkdirSync(join(dir, "src"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), featureFile(verifierBlock, requiredKind, verifierId));
  writeFileSync(join(dir, "src", "thing.ts"), "export function thing() {\n  return 1;\n}\n");

  const bind = runUcJson(
    ["bind", "--repo", ".", "--row", "probe.core.thing", "--file", "src/thing.ts",
      "--mode", "explicit", "--start-line", "1", "--end-line", "3"],
    { cwd: dir, env }
  );
  expect(bind.envelope.ok, `bind failed: ${bind.stderr}`).toBe(true);

  return { dir, env, runKeyPath };
}

interface ScanStatus {
  acceptance_claim: {
    proven: number;
    claimable: boolean;
    by_evidence: { signed_proof: number; local_run: number; performed_run: number };
  };
  summary: Record<string, number>;
  rows: Array<{ row_id: string; local_status: string | null }>;
}

function scan(workspace: Workspace): ScanStatus {
  const { envelope } = runUcJson<{ status: ScanStatus }>(["scan", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
  return envelope.data.status;
}

describe("lifecycle.signals.local_results_are_attested", () => {
  // edge_scan_never_mints_a_key. The keyless tier rests on scan being unable to
  // attest anything, and the only way to see that from outside is that no key
  // file appears where the key would go. Pairing it with verify is what makes
  // the assertion mean something: the absence has to be scan's doing, not the
  // test never reaching the code that mints one.
  test("scan mints no run key, and verify does", () => {
    const workspace = makeWorkspace();
    expect(existsSync(workspace.runKeyPath)).toBe(false);

    const status = scan(workspace);
    expect(
      existsSync(workspace.runKeyPath),
      "scan minted a run key: a read-only command must not be able to attest"
    ).toBe(false);
    expect(status.rows[0].local_status).not.toBe("VERIFIED_LOCAL");

    const verify = runUcJson(["verify", "--repo", ".", "--row", "probe.core.thing"], {
      cwd: workspace.dir,
      env: workspace.env
    });
    expect(verify.envelope.ok).toBe(true);
    expect(
      existsSync(workspace.runKeyPath),
      "verify did not mint a run key, so the previous assertion proves nothing"
    ).toBe(true);
    expect(scan(workspace).rows[0].local_status).toBe("VERIFIED_LOCAL");
  });
});

describe("lifecycle.signals.performed_runs_count", () => {
  // edge_same_row_driven_twice. Driving one behaviour twice must not report two
  // proofs — otherwise the acceptance claim inflates with repetition, which is
  // exactly the dishonest number this row exists to prevent.
  test("one row driven twice is reported once", () => {
    const workspace = makeWorkspace();
    const drive = (key: string) =>
      runUcJson(
        ["evidence", "record", "--repo", ".", "--use-case", "probe.core.thing",
          "--perform", "--idempotency-key", key, "--", "/bin/sh", "-c", "exit 0"],
        { cwd: workspace.dir, env: workspace.env }
      );

    expect(drive("first").envelope.ok).toBe(true);
    const afterOne = scan(workspace);
    expect(afterOne.acceptance_claim.by_evidence.performed_run).toBe(1);
    expect(afterOne.acceptance_claim.claimable).toBe(true);

    expect(drive("second").envelope.ok).toBe(true);
    const afterTwo = scan(workspace);
    expect(
      afterTwo.acceptance_claim.by_evidence.performed_run,
      "driving the same row twice inflated the claim"
    ).toBe(1);
    expect(afterTwo.acceptance_claim.proven).toBe(1);
  });

  // bad_self_reported, the control: a record with no --perform proves nothing,
  // so the number above is the tool's own execution and not merely a record.
  test("a self-reported record proves nothing", () => {
    const workspace = makeWorkspace();
    const recorded = runUcJson(
      ["evidence", "record", "--repo", ".", "--use-case", "probe.core.thing",
        "--summary", "I ran it and it definitely worked."],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(recorded.envelope.ok).toBe(true);

    const status = scan(workspace);
    expect(status.acceptance_claim.by_evidence.performed_run).toBe(0);
    expect(status.acceptance_claim.claimable).toBe(false);
  });
});

describe("lifecycle.signals.run_class_is_derived", () => {
  // A preset verifier carries NO `kind:` — the preset IS the kind, and adding
  // one makes the row invalid. Measured against the schema, not assumed.
  const overclaimingSuite = `        suite:
          preset: python.pytest
          evidence_kind: live_demo`;
  const honestMakeTarget = `        suite:
          preset: make.target
          evidence_kind: live_demo`;

  // bad_overclaimed_live_demo. A named test runner is a unit suite by
  // definition, so a row calling one a live demo is overclaiming in a way the
  // tool can prove — and it must say so without rewriting the author's YAML.
  test("a test-runner preset declaring live_demo is recorded as overclaimed", () => {
    const workspace = makeWorkspace(overclaimingSuite, "live_demo", "suite");
    const { envelope } = runUcJson<{
      results: Array<{ run_class: string; evidence_kind: string; evidence_kind_overclaimed: boolean }>;
      overclaimed_rows: string[];
    }>(["verify", "--repo", ".", "--row", "probe.core.thing"], {
      cwd: workspace.dir,
      env: workspace.env
    });

    const record = envelope.data.results[0];
    expect(record.run_class, "a test-runner preset must record run_class suite").toBe("suite");
    expect(record.evidence_kind_overclaimed).toBe(true);
    expect(record.evidence_kind, "the ledger must not rewrite the author's YAML").toBe("live_demo");
    expect(envelope.data.overclaimed_rows).toContain("probe.core.thing");
  });

  // edge_script_live_demo_is_left_alone, the control: a make target may
  // genuinely drive the product, so the tool cannot call it a lie.
  test("a make target declaring live_demo is left alone", () => {
    const workspace = makeWorkspace(honestMakeTarget, "live_demo", "suite");
    const { envelope } = runUcJson<{
      results: Array<{ run_class: string; evidence_kind_overclaimed: boolean }>;
      overclaimed_rows: string[];
    }>(["verify", "--repo", ".", "--row", "probe.core.thing"], {
      cwd: workspace.dir,
      env: workspace.env
    });

    const record = envelope.data.results[0];
    expect(record.run_class).toBe("command");
    expect(record.evidence_kind_overclaimed).toBe(false);
    expect(envelope.data.overclaimed_rows).not.toContain("probe.core.thing");
  });
});
