// The black-box oracle for lifecycle/signals.yml.
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
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
  verifierId = "script",
  bind = true
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

  if (bind) {
    const bound = runUcJson(
      ["bind", "--repo", ".", "--row", "probe.core.thing", "--file", "src/thing.ts",
        "--mode", "explicit", "--start-line", "1", "--end-line", "3"],
      { cwd: dir, env }
    );
    expect(bound.envelope.ok, `bind failed: ${bound.stderr}`).toBe(true);
  }

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

/** The unsigned results ledger `uc verify` writes by default. */
function resultsLedger(workspace: Workspace): string {
  return join(workspace.dir, ".use-cases", "verification-results.jsonl");
}

function readOnlyRecord(workspace: Workspace): Record<string, unknown> {
  const lines = readFileSync(resultsLedger(workspace), "utf8").trim().split("\n");
  expect(lines, "expected exactly one results record").toHaveLength(1);
  return JSON.parse(lines[0]) as Record<string, unknown>;
}

function writeRecord(workspace: Workspace, record: Record<string, unknown>): void {
  writeFileSync(resultsLedger(workspace), `${JSON.stringify(record)}\n`);
}

/** Bind, verify, and hand back the genuine attested record verify wrote. */
function verifiedWorkspace(): { workspace: Workspace; record: Record<string, unknown> } {
  const workspace = makeWorkspace();
  const verify = runUcJson(["verify", "--repo", ".", "--row", "probe.core.thing"], {
    cwd: workspace.dir,
    env: workspace.env
  });
  expect(verify.envelope.ok).toBe(true);
  return { workspace, record: readOnlyRecord(workspace) };
}

//: @use-case:lifecycle.signals.local_results_are_attested#blackbox
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

  // golden_real_run. The record verify wrote carries an attestation, and that
  // is what makes it count — not the hashes, which anything can compute.
  test("a record uc verify wrote carries an attestation and reads VERIFIED_LOCAL", () => {
    const { workspace, record } = verifiedWorkspace();
    expect(record.run_attestation, "verify must attest every record it emits").toMatch(/^hmac-sha256:/);
    expect(record.status).toBe("pass");

    const status = scan(workspace);
    expect(status.rows[0].local_status).toBe("VERIFIED_LOCAL");
    expect(status.summary.unattested_local).toBe(0);
  });

  // bad_typed_line. The whole point of the keyless tier: byte-perfect hashes
  // prove nothing, because anything that can read the repo can compute them.
  // Only the run key the tool holds separates a run from a text edit.
  test("a hand-written record with byte-perfect hashes reads UNATTESTED_LOCAL", () => {
    const { workspace, record } = verifiedWorkspace();
    const { run_attestation: _dropped, ...typedByHand } = record;
    writeRecord(workspace, typedByHand);

    const status = scan(workspace);
    expect(
      status.rows[0].local_status,
      "hashes alone must never buy a green"
    ).toBe("UNATTESTED_LOCAL");
    expect(status.summary.unattested_local).toBe(1);
    expect(status.acceptance_claim.by_evidence.local_run).toBe(0);
    expect(status.acceptance_claim.claimable).toBe(false);
  });

  // bad_edited_record. Editing ANY field invalidates the attestation, which is
  // what stops a failure being laundered into a pass after the fact.
  test("editing an attested record invalidates it, including flipping a failure to a pass", () => {
    const { workspace, record } = verifiedWorkspace();
    writeRecord(workspace, { ...record, exit_code: 1, status: "fail" });
    expect(scan(workspace).rows[0].local_status).toBe("UNATTESTED_LOCAL");

    // And the direction that actually matters: a laundered pass.
    writeRecord(workspace, { ...record, exit_code: 0, status: "pass", stdout_sha256: "sha256:deadbeef" });
    expect(
      scan(workspace).rows[0].local_status,
      "a record edited to say pass must not read as proven"
    ).toBe("UNATTESTED_LOCAL");
  });

  // edge_ledger_from_another_machine. Someone else's run is not your evidence,
  // so a ledger committed by a teammate reads unattested on your machine.
  test("a results ledger attested on another machine reads unattested here", () => {
    const { workspace, record } = verifiedWorkspace();
    expect(scan(workspace).rows[0].local_status).toBe("VERIFIED_LOCAL");

    // Same repo, same ledger, different machine-local run key.
    const otherMachine = { ...workspace, env: { UC_RUN_KEY_FILE: join(workspace.dir, "machine-b", "run-key") } };
    writeRecord(workspace, record);
    expect(
      scan(otherMachine).rows[0].local_status,
      "another machine's attestation must not verify here"
    ).toBe("UNATTESTED_LOCAL");
  });
});
//: @use-case:end lifecycle.signals.local_results_are_attested#blackbox

/** Drive the behaviour through the tool, which is what a performed run means. */
function drive(workspace: Workspace, key: string, argv: string[]) {
  return runUcJson(
    ["evidence", "record", "--repo", ".", "--use-case", "probe.core.thing",
      "--perform", "--idempotency-key", key, "--", ...argv],
    { cwd: workspace.dir, env: workspace.env }
  );
}

//: @use-case:lifecycle.signals.performed_runs_count#blackbox
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
  // golden_driven. The claim reads the ledger of behaviour actually driven.
  test("a tool-executed passing run proves its row and counts under performed_run", () => {
    const workspace = makeWorkspace();
    const driven = drive(workspace, "golden", ["/bin/sh", "-c", "exit 0"]);
    expect(driven.envelope.ok).toBe(true);

    const status = scan(workspace);
    expect(status.acceptance_claim.by_evidence.performed_run).toBe(1);
    expect(status.acceptance_claim.proven).toBe(1);
    expect(status.acceptance_claim.claimable).toBe(true);
  });

  // bad_failing_run_proves_nothing. Driving a behaviour and watching it fail is
  // still a performed run — it just is not proof that the behaviour holds.
  test("a failing run does not prove the behaviour holds", () => {
    const workspace = makeWorkspace();
    drive(workspace, "failing", ["/bin/sh", "-c", "exit 1"]);

    const status = scan(workspace);
    expect(status.acceptance_claim.by_evidence.performed_run).toBe(0);
    expect(status.acceptance_claim.claimable).toBe(false);
  });

  // bad_voided_record_does_not_count. Voiding is how a mistake is corrected in
  // an append-only ledger, so the claim has to follow the correction.
  test("a voided record stops counting", () => {
    const workspace = makeWorkspace();
    const driven = drive(workspace, "voidable", ["/bin/sh", "-c", "exit 0"]);
    expect(scan(workspace).acceptance_claim.by_evidence.performed_run).toBe(1);

    const event = (driven.envelope.data as { event: { aggregate_id: string; event_id: string } }).event;
    const voided = runUcJson(
      ["evidence", "void", "--repo", ".", "--evidence", event.aggregate_id,
        "--expected-head", event.event_id, "--reason", "recorded against the wrong row"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(voided.envelope.ok).toBe(true);
    expect(scan(workspace).acceptance_claim.by_evidence.performed_run).toBe(0);
  });

  // edge_row_edited_after_the_run. This tier decays like every other: a run
  // proved the row as it was, not the row as it now is.
  test("editing the row invalidates the run that proved the old one", () => {
    const workspace = makeWorkspace();
    drive(workspace, "before-edit", ["/bin/sh", "-c", "exit 0"]);
    expect(scan(workspace).acceptance_claim.by_evidence.performed_run).toBe(1);

    const featurePath = join(workspace.dir, "use-cases", "probe.yml");
    writeFileSync(
      featurePath,
      readFileSync(featurePath, "utf8").replace("title: The thing works", "title: The thing works, retitled")
    );
    expect(
      scan(workspace).acceptance_claim.by_evidence.performed_run,
      "a run recorded against a since-edited row must stop counting"
    ).toBe(0);
  });

  // edge_unbound_row_cannot_be_driven_into_proof. Driving something and naming
  // an unbound row must not manufacture coverage the row never had.
  test("an unbound row cannot be proven by driving something and naming it", () => {
    const workspace = makeWorkspace(PASSING_SCRIPT, "test_result", "script", false);
    drive(workspace, "unbound", ["/bin/sh", "-c", "exit 0"]);

    const status = scan(workspace);
    expect(status.rows[0].status).toBe("UNBOUND");
    expect(status.acceptance_claim.proven).toBe(0);
    expect(status.acceptance_claim.claimable).toBe(false);
  });

  // bad_observed_command_is_not_a_run. A record may name a full command line
  // and still be nothing more than a claim. What counts is that the TOOL ran
  // it, which is why the producer and verifier matter as much as the argv.
  test("a command the tool merely observed is not a run it executed", () => {
    const workspace = makeWorkspace();
    const driven = drive(workspace, "observed", ["/bin/sh", "-c", "exit 0"]);
    expect(scan(workspace).acceptance_claim.by_evidence.performed_run).toBe(1);

    // Same argv, downgraded to something an agent merely watched.
    const ledgerPath = join(
      workspace.dir,
      (driven.envelope.data as { ledger_path: string }).ledger_path
    );
    const event = JSON.parse(readFileSync(ledgerPath, "utf8").trim().split("\n")[0]) as {
      payload: Record<string, unknown>;
    };
    // `method.type` is the tell, not the argv: replay reads structured_command
    // as "the tool executed this", and anything else as a report or an
    // observation. A human who WATCHED a command and wrote down its argv lands
    // here — a real observation, and still not a run the tool performed.
    const method = event.payload.method as { executable: string; argv: string[] };
    event.payload.method = { type: "observed", executable: method.executable, argv: method.argv };
    writeFileSync(ledgerPath, `${JSON.stringify(event)}\n`);

    const observed = scan(workspace);
    expect(
      observed.acceptance_claim.by_evidence.performed_run,
      "argv alone must not make a claim into a run"
    ).toBe(0);
    expect(observed.acceptance_claim.claimable).toBe(false);
  });

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
//: @use-case:end lifecycle.signals.performed_runs_count#blackbox

//: @use-case:lifecycle.signals.run_class_is_derived#blackbox
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
  const honestSuite = `        suite:
          preset: python.pytest
          evidence_kind: test_result`;

  // golden_suite_preset. A named test runner IS a unit suite, by definition.
  test("a test-runner preset records run_class suite", () => {
    const workspace = makeWorkspace(honestSuite, "test_result", "suite");
    const { envelope } = runUcJson<{ results: Array<{ run_class: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.thing"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(envelope.data.results[0].run_class).toBe("suite");
  });

  // golden_arbitrary_script_is_a_command. Anything else is a command, and
  // verify never mints a journey — spawning a process is not a demonstration.
  test("an arbitrary script records run_class command, never suite or journey", () => {
    const workspace = makeWorkspace();
    const { envelope } = runUcJson<{ results: Array<{ run_class: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.thing"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(envelope.data.results[0].run_class).toBe("command");
    expect(envelope.data.results[0].run_class).not.toBe("journey");
  });

  // edge_declared_evidence_kind_is_preserved. Overclaim is recorded as a flag
  // BESIDE the claim; the ledger corrects nobody's YAML.
  test("the declared evidence_kind is preserved verbatim alongside the overclaim flag", () => {
    const workspace = makeWorkspace(overclaimingSuite, "live_demo", "suite");
    const { envelope } = runUcJson<{
      results: Array<{ evidence_kind: string; evidence_kind_overclaimed: boolean }>;
    }>(["verify", "--repo", ".", "--row", "probe.core.thing"], {
      cwd: workspace.dir,
      env: workspace.env
    });
    expect(envelope.data.results[0].evidence_kind).toBe("live_demo");
    expect(envelope.data.results[0].evidence_kind_overclaimed).toBe(true);
  });

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
//: @use-case:end lifecycle.signals.run_class_is_derived#blackbox
