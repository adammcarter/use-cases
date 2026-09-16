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
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUc, runUcJson } from "../helpers/uc-binary";

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


// ---------------------------------------------------------------------------
// A multi-row fixture. The rows above need only one behaviour; the four below
// are about how rows affect EACH OTHER — one row's verify preserving another's
// evidence, one unbound row blocking the whole claim — so they need a
// workspace with several.
// ---------------------------------------------------------------------------

interface MultiRowOptions {
  /** Rows to create. Every one gets a source file and a passing verifier. */
  rows: string[];
  /** Rows to bind. Anything omitted stays deliberately UNBOUND. */
  bind?: string[];
  /** Give this row a verifier that cannot resolve, for the blocked-plan case. */
  unresolvable?: string;
}

function makeMultiRowWorkspace(options: MultiRowOptions): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-multi-"));
  tempDirs.push(dir);
  const runKeyPath = join(dir, "machine", "run-key");
  const env = { UC_RUN_KEY_FILE: runKeyPath };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  mkdirSync(join(dir, "src"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);

  const header = "schema_version: 1\nfeature:\n  id: probe.core\n  name: Probe\n  summary: Probe.\nuse_cases:\n";
  const body = options.rows
    .map((name) => {
      // A plan reports `blocked` when NO verifier resolves. A missing executable
      // is not that case — the plan never stats the binary, so it still says
      // "run" — and nor is an unknown preset, which the schema refuses outright.
      // Requiring a verifier the policy never defines is the real shape, and it
      // is the same defect 22 rows in this repo's own matrix carry.
      const verifier =
        options.unresolvable === name
          ? `        other:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", "exit 0"]
          inputs: ["src/${name}.ts"]`
          : `        script:
          kind: script
          evidence_kind: test_result
          command: ["/bin/sh", "-c", "exit 0"]
          inputs: ["src/${name}.ts"]`;
      return `  - id: probe.core.${name}
    title: Row ${name}
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Probe row ${name}.
    preconditions: [A source file exists.]
    trigger: An agent verifies.
    scenarios:
      - id: probe.core.${name}.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [It passes.]
    observable_outcomes: [The row reaches VERIFIED_LOCAL.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
${verifier}
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
    approval_policy:
      mode: none
`;
    })
    .join("");
  writeFileSync(join(dir, "use-cases", "probe.yml"), header + body);
  for (const name of options.rows) {
    // Lines 1-3 are the bound span. The helper below it exists so a test can
    // edit the file WITHOUT hitting the span — which is the whole distinction
    // impact_leads_with_the_union turns on.
    writeFileSync(
      join(dir, "src", `${name}.ts`),
      `export function ${name}() {\n  return 1;\n}\n\nexport function ${name}Helper() {\n  return 2;\n}\n`
    );
  }

  const workspace: Workspace = { dir, env, runKeyPath };
  for (const name of options.bind ?? options.rows) {
    const bound = runUcJson(
      ["bind", "--repo", ".", "--row", `probe.core.${name}`, "--file", `src/${name}.ts`,
        "--mode", "explicit", "--start-line", "1", "--end-line", "3"],
      { cwd: dir, env }
    );
    expect(bound.envelope.ok, `bind ${name} failed: ${bound.stderr}`).toBe(true);
  }
  return workspace;
}

function ledgerLineCount(workspace: Workspace): number {
  return readFileSync(resultsLedger(workspace), "utf8").trim().split("\n").filter(Boolean).length;
}

function verifyAll(workspace: Workspace) {
  return runUcJson(["verify", "--repo", ".", "--all"], { cwd: workspace.dir, env: workspace.env });
}

function verifyRow(workspace: Workspace, row: string) {
  return runUcJson(["verify", "--repo", ".", "--row", `probe.core.${row}`], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

function rowStatus(workspace: Workspace, row: string) {
  return scan(workspace).rows.find((r) => r.row_id === `probe.core.${row}`);
}

//: @use-case:lifecycle.signals.verify_preserves_other_rows#blackbox
describe("lifecycle.signals.verify_preserves_other_rows", () => {
  // golden_single_row. The incremental loop the docs recommend has to be safe:
  // verifying one row must not cost another row its evidence.
  test("verifying one row leaves every other row's evidence intact", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    verifyAll(workspace);
    expect(rowStatus(workspace, "beta")?.local_status).toBe("VERIFIED_LOCAL");

    verifyRow(workspace, "alpha");
    expect(
      rowStatus(workspace, "beta")?.local_status,
      "a row the run did not target must keep its evidence"
    ).toBe("VERIFIED_LOCAL");
    expect(rowStatus(workspace, "alpha")?.local_status).toBe("VERIFIED_LOCAL");
  });

  // golden_replaces_prior_record. Re-verifying replaces, it does not accrete —
  // otherwise the ledger would grow a record per run and readers would have to
  // guess which one is current.
  test("re-verifying a row replaces its prior record rather than duplicating it", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    verifyAll(workspace);
    expect(ledgerLineCount(workspace)).toBe(2);

    verifyRow(workspace, "alpha");
    expect(ledgerLineCount(workspace), "one record per row, not one per run").toBe(2);
  });

  // bad_retained_evidence_is_rechecked. Preserving a record is not the same as
  // trusting it: a row whose code moved is demoted, not left falsely green.
  test("retained evidence is still re-checked, so a changed row goes STALE not green", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    verifyAll(workspace);
    expect(rowStatus(workspace, "beta")?.local_status).toBe("VERIFIED_LOCAL");

    // Change beta's bound code INSIDE its span, without re-verifying it.
    // Rewriting the whole file would delete the markers bind inserted and make
    // the row UNBOUND, which measures something else entirely.
    const betaPath = join(workspace.dir, "src", "beta.ts");
    writeFileSync(betaPath, readFileSync(betaPath, "utf8").replace("return 1;", "return 2;"));
    verifyRow(workspace, "alpha");

    expect(
      rowStatus(workspace, "beta")?.local_status,
      "a row whose code changed must be demoted rather than kept green"
    ).toBe("STALE_LOCAL");
  });

  // edge_no_targets. A run that matches nothing must write nothing away.
  test("verifying an UNBOUND row targets nothing and leaves the ledger intact", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta", "gamma"], bind: ["alpha", "beta"] });
    verifyAll(workspace);
    const before = ledgerLineCount(workspace);

    const result = verifyRow(workspace, "gamma");
    expect(result.envelope.ok).toBe(true);
    expect((result.envelope.data as { results: unknown[] }).results).toHaveLength(0);
    expect(ledgerLineCount(workspace), "a run that targeted nothing must write nothing away").toBe(before);
  });
});
//: @use-case:end lifecycle.signals.verify_preserves_other_rows#blackbox

//: @use-case:lifecycle.signals.acceptance_claim_is_honest#blackbox
describe("lifecycle.signals.acceptance_claim_is_honest", () => {
  // bad_nothing_proven. The field an agent quotes must say NOT_SUPPORTED while
  // nothing is proven, even though the policy guard is green — the guard is
  // only saying nothing is BLOCKING.
  test("with nothing proven the claim is NOT_SUPPORTED even though the guard is green", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    const status = scan(workspace);
    expect(status.acceptance_claim.claimable).toBe(false);
    expect(status.acceptance_claim.statement).toContain("NOT_SUPPORTED");
    expect(status.acceptance_claim.proven).toBe(0);
  });

  // golden_all_proven. With every row proven the claim is claimable and names
  // how many behaviours back it.
  test("with every row proven the claim is claimable and counts what backs it", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    verifyAll(workspace);

    const status = scan(workspace);
    expect(status.acceptance_claim.claimable).toBe(true);
    expect(status.acceptance_claim.proven).toBe(2);
    expect(status.acceptance_claim.by_evidence.local_run).toBe(2);
  });

  // bad_unbound_row_blocks_the_claim. An UNBOUND row is never counted as
  // proven, so one unbound row is enough to stop the whole claim.
  test("an unbound row is never counted as proven, so it blocks the claim", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta", "gamma"], bind: ["alpha", "beta"] });
    verifyAll(workspace);

    const status = scan(workspace);
    expect(rowStatus(workspace, "gamma")?.status).toBe("UNBOUND");
    expect(status.acceptance_claim.claimable, "one unbound row blocks the claim").toBe(false);
    expect(status.acceptance_claim.proven).toBe(2);
  });

  // edge_local_axis_counted_alongside_signed. A green KEYLESS matrix must not
  // read as a failing one just because nothing is signed.
  test("the local axis is counted alongside the signed axis", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    verifyAll(workspace);

    const status = scan(workspace);
    expect(status.summary.verified_local).toBe(2);
    expect(status.summary.unproven, "signed status stays UNPROVEN with no keys").toBe(2);
    expect(status.acceptance_claim.by_evidence.signed_proof).toBe(0);
    expect(status.acceptance_claim.claimable, "keyless green is still green").toBe(true);
  });
});
//: @use-case:end lifecycle.signals.acceptance_claim_is_honest#blackbox

//: @use-case:lifecycle.signals.verify_can_be_previewed#blackbox
describe("lifecycle.signals.verify_can_be_previewed", () => {
  // golden_dry_run. The plan names each targeted row and the exact command.
  test("the plan names each targeted row and the command that would run", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    const { envelope } = runUcJson<{
      planned: Array<{ row_id: string; command: string[]; disposition: string }>;
      dry_run: boolean;
    }>(["verify", "--repo", ".", "--all", "--dry-run"], { cwd: workspace.dir, env: workspace.env });

    expect(envelope.data.dry_run).toBe(true);
    expect(envelope.data.planned.map((p) => p.row_id).sort()).toEqual(["probe.core.alpha", "probe.core.beta"]);
    expect(envelope.data.planned[0].command).toEqual(["/bin/sh", "-c", "exit 0"]);
    expect(envelope.data.planned[0].disposition).toBe("run");
  });

  // bad_unresolvable_verifier_is_blocked. A row the plan cannot run must be
  // reported as blocked, not quietly dropped — a plan that omits a row
  // under-reports the very cost it was asked for.
  test("a row whose verifier cannot be resolved is reported as blocked, not skipped", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"], unresolvable: "beta" });
    const { envelope } = runUcJson<{ planned: Array<{ row_id: string; disposition: string }> }>(
      ["verify", "--repo", ".", "--all", "--dry-run"],
      { cwd: workspace.dir, env: workspace.env }
    );

    const beta = envelope.data.planned.find((p) => p.row_id === "probe.core.beta");
    expect(beta, "the unresolvable row must still appear in the plan").toBeDefined();
    expect(beta?.disposition).not.toBe("run");
  });

  // edge_nothing_is_executed_or_written. A plan is never evidence.
  test("a dry run executes nothing, writes no ledger and mints no record", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha", "beta"] });
    const { envelope } = runUcJson<{ results: unknown[]; out_path: string | null }>(
      ["verify", "--repo", ".", "--all", "--dry-run"],
      { cwd: workspace.dir, env: workspace.env }
    );

    expect(envelope.data.results).toHaveLength(0);
    expect(envelope.data.out_path).toBeNull();
    expect(existsSync(resultsLedger(workspace)), "a plan must write no results ledger").toBe(false);
    expect(rowStatus(workspace, "alpha")?.local_status).not.toBe("VERIFIED_LOCAL");
  });
});
//: @use-case:end lifecycle.signals.verify_can_be_previewed#blackbox

//: @use-case:lifecycle.signals.bind_names_the_next_step#blackbox
describe("lifecycle.signals.bind_names_the_next_step", () => {
  // golden_after_bind. Rows were being bound and then abandoned; a successful
  // bind ends with the command that actually proves the behaviour.
  test("a successful bind hands back the verify command for that row", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"], bind: [] });
    const { envelope } = runUcJson<{ next_command: string; binding_slug: string }>(
      ["bind", "--repo", ".", "--row", "probe.core.alpha", "--file", "src/alpha.ts",
        "--mode", "explicit", "--start-line", "1", "--end-line", "3"],
      { cwd: workspace.dir, env: workspace.env }
    );

    expect(envelope.ok).toBe(true);
    expect(envelope.data.next_command).toBe("uc verify --row probe.core.alpha");
  });

  // edge_bind_alone_is_not_proof. Binding says where the behaviour lives; it
  // says nothing about whether it works.
  test("binding alone never moves a row to a proven state", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    const row = rowStatus(workspace, "alpha");
    expect(row?.status).toBe("UNPROVEN");
    expect(row?.local_status).toBe("UNVERIFIED_LOCAL");
    expect(scan(workspace).acceptance_claim.claimable).toBe(false);
  });
});
//: @use-case:end lifecycle.signals.bind_names_the_next_step#blackbox


/** A bare git repo with no workspace, for the commands that create one. */
function makeBareRepo(existingGitignore?: string): { dir: string; env: Record<string, string> } {
  const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-bare-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  runUc(["--version"], { cwd: dir, env });
  spawnGit(dir, ["init", "-q", "."]);
  spawnGit(dir, ["config", "user.email", "probe@example.com"]);
  spawnGit(dir, ["config", "user.name", "Probe"]);
  if (existingGitignore !== undefined) writeFileSync(join(dir, ".gitignore"), existingGitignore);
  return { dir, env };
}

function spawnGit(cwd: string, args: string[]): void {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${result.stderr}`);
}

//: @use-case:lifecycle.signals.impact_leads_with_the_union#blackbox
describe("lifecycle.signals.impact_leads_with_the_union", () => {
  function editedWorkspace(replace: [string, string]): Workspace {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    spawnGit(workspace.dir, ["init", "-q", "."]);
    spawnGit(workspace.dir, ["config", "user.email", "probe@example.com"]);
    spawnGit(workspace.dir, ["config", "user.name", "Probe"]);
    spawnGit(workspace.dir, ["add", "-A"]);
    spawnGit(workspace.dir, ["commit", "-qm", "base"]);
    const path = join(workspace.dir, "src", "alpha.ts");
    writeFileSync(path, readFileSync(path, "utf8").replace(replace[0], replace[1]));
    return workspace;
  }

  // golden_touched_not_hit. Editing a bound file BELOW its span hits no span,
  // and the headline must still count it.
  test("the headline counts span-hit and file-touched rows together", () => {
    const workspace = editedWorkspace(["return 2;", "return 3;"]);
    const { envelope } = runUcJson<{ summary: string; impacted: unknown[]; touched: Array<{ row_id: string }> }>(
      ["impact", "--repo", "."],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(envelope.data.impacted).toHaveLength(0);
    expect(envelope.data.touched.map((t) => t.row_id)).toEqual(["probe.core.alpha"]);
    expect(envelope.data.summary).toContain("1 touched");
  });

  // bad_never_reports_nothing_impacted. The failure this row exists to stop: an
  // agent reads the headline, sees nothing, and skips re-verifying.
  test("it never reports nothing impacted while a bound file was touched", () => {
    const workspace = editedWorkspace(["return 2;", "return 3;"]);
    const human = runUc(["impact", "--repo", "."], { cwd: workspace.dir, env: workspace.env });
    expect(human.status).toBe(0);
    expect(human.stdout).not.toMatch(/^0 behaviours? (may be )?impacted by your change$/m);
    expect(human.stdout).toContain("re-verify");
    expect(human.stdout).toContain("file-touched");
  });

  // edge_touched_row_carries_the_same_command. Being conservative costs one
  // re-verify; being wrong ships a regression. So a touched row is told to
  // re-verify exactly as a span-hit row is.
  test("a touched row is told to re-verify, the same as a span-hit row", () => {
    const touched = editedWorkspace(["return 2;", "return 3;"]);
    const hit = editedWorkspace(["return 1;", "return 9;"]);

    const touchedOut = runUc(["impact", "--repo", "."], { cwd: touched.dir, env: touched.env }).stdout;
    const hitOut = runUc(["impact", "--repo", "."], { cwd: hit.dir, env: hit.env }).stdout;

    expect(touchedOut).toContain("probe.core.alpha");
    expect(hitOut).toContain("probe.core.alpha");
    expect(touchedOut).toContain("re-verify");
    expect(hitOut).toContain("re-verify");
  });
});
//: @use-case:end lifecycle.signals.impact_leads_with_the_union#blackbox

//: @use-case:lifecycle.signals.transient_output_stays_out_of_git#blackbox
describe("lifecycle.signals.transient_output_stays_out_of_git", () => {
  const TRANSIENT = ["showcase-runs/", ".use-cases/verification-results.jsonl"];

  // golden_fresh_repo. The tool must not break the adopter's own clean-tree gate.
  test("init gitignores its own transient output in a repo with no .gitignore", () => {
    const repo = makeBareRepo();
    const init = runUcJson(["init", "--repo", "."], { cwd: repo.dir, env: repo.env });
    expect(init.envelope.ok).toBe(true);

    const gitignore = readFileSync(join(repo.dir, ".gitignore"), "utf8");
    for (const entry of TRANSIENT) expect(gitignore).toContain(entry);
  });

  // edge_existing_gitignore_is_appended_to. Never rewritten, never reordered.
  test("an existing .gitignore is appended to, never rewritten or reordered", () => {
    const original = "node_modules/\n*.log\n";
    const repo = makeBareRepo(original);
    runUcJson(["init", "--repo", "."], { cwd: repo.dir, env: repo.env });

    const gitignore = readFileSync(join(repo.dir, ".gitignore"), "utf8");
    expect(gitignore.startsWith(original), "the adopter's entries keep their place").toBe(true);
    for (const entry of TRANSIENT) expect(gitignore).toContain(entry);
  });

  // edge_rerun_does_not_duplicate. A second init is refused outright, which is
  // what makes duplicate entries impossible rather than merely unlikely.
  test("a second init is refused, so the entries cannot accumulate", () => {
    const repo = makeBareRepo();
    runUcJson(["init", "--repo", "."], { cwd: repo.dir, env: repo.env });
    const before = readFileSync(join(repo.dir, ".gitignore"), "utf8");

    const second = runUcJson(["init", "--repo", "."], { cwd: repo.dir, env: repo.env });
    expect(second.envelope.ok).toBe(false);
    expect(JSON.stringify(second.envelope.diagnostics)).toContain("workspace_exists");
    expect(readFileSync(join(repo.dir, ".gitignore"), "utf8")).toBe(before);
    for (const entry of TRANSIENT) {
      expect(before.split(entry).length - 1, `${entry} must appear once`).toBe(1);
    }
  });
});
//: @use-case:end lifecycle.signals.transient_output_stays_out_of_git#blackbox

//: @use-case:lifecycle.signals.nested_workspace_is_not_scanned#blackbox
describe("lifecycle.signals.nested_workspace_is_not_scanned", () => {
  /** Put a nested workspace, with its own config and a marked file, at `where`. */
  function withNestedWorkspace(workspace: Workspace, where: string): void {
    const nested = join(workspace.dir, where);
    mkdirSync(join(nested, "src"), { recursive: true });
    mkdirSync(join(nested, "use-cases"), { recursive: true });
    writeFileSync(join(nested, "use-cases.yml"), WORKSPACE_CONFIG);
    writeFileSync(
      join(nested, "use-cases", "n.yml"),
      `schema_version: 1
feature:
  id: nested.row
  name: Nested
  summary: A workspace nested inside another one.
use_cases:
  - id: nested.row.one
    title: The nested behaviour
    lifecycle: planned
    value_tier: supporting
    journey_role: golden
    usage_frequency: rare
`
    );
    writeFileSync(
      join(nested, "src", "n.ts"),
      "//: @use-case:nested.row.one\nexport function nested() { return 1; }\n//: @use-case:end nested.row.one\n"
    );
  }

  // golden_nested_fixture_is_skipped.
  test("a directory carrying its own use-cases.yml is not walked by the parent", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    withNestedWorkspace(workspace, "tests/fixtures/nested");
    const status = scan(workspace);
    expect(status.rows.map((r) => r.row_id)).toEqual(["probe.core.alpha"]);
  });

  // bad_no_parent_diagnostics_for_nested_markers. The nested workspace's rows
  // exist only in ITS matrix, so charging them to the parent would fail the
  // parent's integrity gate for something that is not its business.
  test("the parent emits no integrity or registry errors for nested markers", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    withNestedWorkspace(workspace, "tests/fixtures/nested");
    const { envelope } = runUcJson<{
      status: { integrity_errors: unknown[] };
      registry_errors: unknown[];
    }>(["scan", "--repo", "."], { cwd: workspace.dir, env: workspace.env });

    expect(envelope.data.status.integrity_errors).toHaveLength(0);
    expect(envelope.data.registry_errors).toHaveLength(0);
  });

  // edge_any_directory_name. The rule keys on the CONFIG, not on a blessed
  // directory name, so a newly added nested workspace needs no skip entry.
  test("it is skipped because of its config, whatever the directory is called", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    withNestedWorkspace(workspace, "vendor/demo-app");
    const status = scan(workspace);
    expect(status.rows.map((r) => r.row_id)).toEqual(["probe.core.alpha"]);
  });

  // edge_root_config_does_not_skip_the_repo. The check applies to CHILD
  // directories: the product root's own config must not skip everything.
  test("the product root's own config does not skip the whole repository", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    const status = scan(workspace);
    expect(status.rows).toHaveLength(1);
    expect(status.rows[0].row_id).toBe("probe.core.alpha");
  });

  // edge_nested_workspace_still_scans_itself. Its config sits at ITS product
  // root rather than below it, so pointing scan at it works normally.
  test("the nested workspace's own scan is unaffected", () => {
    const workspace = makeMultiRowWorkspace({ rows: ["alpha"] });
    withNestedWorkspace(workspace, "vendor/demo-app");
    const { envelope } = runUcJson<{ status: { rows: Array<{ row_id: string }> } }>(
      ["scan", "--repo", "vendor/demo-app"],
      { cwd: workspace.dir, env: workspace.env }
    );
    // The claim is that the nested workspace scans ITSELF — it sees its own row
    // and none of the parent's. Its exit code is not the point.
    const ids = envelope.data.status.rows.map((r) => r.row_id);
    expect(ids).toContain("nested.row.one");
    expect(ids).not.toContain("probe.core.alpha");
  });
});
//: @use-case:end lifecycle.signals.nested_workspace_is_not_scanned#blackbox


//: @use-case:lifecycle.signals.variant_fanout#blackbox
describe("lifecycle.signals.variant_fanout", () => {
  /** A family whose verifier passes for every variant except `failing`. */
  function makeFamily(options: { token?: boolean; failing?: string } = {}): Workspace {
    const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-fam-"));
    tempDirs.push(dir);
    const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
    mkdirSync(join(dir, "use-cases"), { recursive: true });
    mkdirSync(join(dir, "src"), { recursive: true });
    writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
    const command =
      options.token === false
        ? '["/bin/sh", "-c", "exit 0"]'
        : `["/bin/sh", "-c", "test {variant} != ${options.failing ?? "__none__"}"]`;
    writeFileSync(
      join(dir, "use-cases", "probe.yml"),
      `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.fam
    title: Variant family
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Probe variant fan-out.
    preconditions: [A source file exists.]
    trigger: An agent verifies the family.
    scenarios:
      - id: probe.core.fam.golden_runs
        kind: steps
        steps: [Run it.]
        observable_outcomes: [Each variant gets its own record.]
    observable_outcomes: [Each variant gets its own record.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        script:
          kind: script
          evidence_kind: test_result
          command: ${command}
          inputs: ["src/fam.ts"]
      requirements:
        - evidence_kind: test_result
          required_verifiers: [script]
          minimum_count: 1
    approval_policy:
      mode: none
    variants:
      - key: good
        title: A passing variant
      - key: other
        title: Another variant
`
    );
    writeFileSync(join(dir, "src", "fam.ts"), "export function fam() {\n  return 1;\n}\n");
    const bound = runUcJson(
      ["bind", "--repo", ".", "--row", "probe.core.fam", "--file", "src/fam.ts",
        "--mode", "explicit", "--start-line", "1", "--end-line", "3"],
      { cwd: dir, env }
    );
    expect(bound.envelope.ok, `bind failed: ${bound.stderr}`).toBe(true);
    return { dir, env, runKeyPath: join(dir, "machine", "run-key") };
  }

  // golden_loop. One spawn per declared variant, one record each, keyed
  // family::variant, so a reader can see which shape was proved.
  test("variant_fanout spawn — each variant gets its own ledger record keyed family::variant", () => {
    const workspace = makeFamily();
    const { envelope } = runUcJson<{ results: Array<{ row_id: string; status: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.fam"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(envelope.data.results.map((r) => r.row_id).sort()).toEqual([
      "probe.core.fam::good",
      "probe.core.fam::other"
    ]);
  });

  // golden_family_verified_only_when_all_pass.
  test("variant_fanout verdict — the family is VERIFIED_LOCAL only when every variant passes", () => {
    const workspace = makeFamily();
    runUcJson(["verify", "--repo", ".", "--row", "probe.core.fam"], {
      cwd: workspace.dir,
      env: workspace.env
    });
    expect(scan(workspace).rows[0].local_status).toBe("VERIFIED_LOCAL");
  });

  // bad_failing_variant_is_named. A partial failure must be reported as one,
  // and the failing shape named rather than left to be hunted.
  test("variant_fanout names verdict — a failing variant keeps the family out of green, is named, and fails the run", () => {
    const workspace = makeFamily({ failing: "other" });
    const result = runUcJson<{ exit_code: number; results: Array<{ row_id: string; status: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.fam"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(result.envelope.data.exit_code, "a partial failure is not success").not.toBe(0);

    const row = scan(workspace).rows[0] as { local_status: string; local_reason?: string };
    expect(row.local_status).not.toBe("VERIFIED_LOCAL");
    expect(JSON.stringify(row), "the failing variant must be named").toContain("other");
  });

  // bad_missing_variant_token_is_a_spec_error. A family whose command cannot
  // distinguish its variants is a spec error, surfaced once — never a false pass.
  test("variant_fanout spawn — a family with no {variant} token is a spec error and spawns nothing", () => {
    const workspace = makeFamily({ token: false });
    const { envelope } = runUcJson<{ exit_code: number; errors: Array<{ code: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.fam"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(envelope.data.exit_code).not.toBe(0);
    const codes = envelope.data.errors.map((e) => e.code);
    expect(codes).toContain("VARIANT_TOKEN_MISSING");
    expect(codes.filter((c) => c === "VARIANT_TOKEN_MISSING"), "surfaced once, not per variant").toHaveLength(1);
    expect(scan(workspace).rows[0].local_status).not.toBe("VERIFIED_LOCAL");
  });

  // edge_dry_run_previews_each_variant, both ways: one entry per variant, and a
  // token-less family previewing as blocked rather than as a run.
  test("variant_fanout dry — previews one entry per variant, and blocked when the token is missing", () => {
    const fanned = runUcJson<{ planned: Array<{ row_id: string; disposition: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.fam", "--dry-run"],
      { cwd: makeFamily().dir, env: { UC_RUN_KEY_FILE: "/dev/null" } }
    );
    expect(fanned.envelope.data.planned.map((p) => p.row_id).sort()).toEqual([
      "probe.core.fam::good",
      "probe.core.fam::other"
    ]);

    const tokenless = makeFamily({ token: false });
    const { envelope } = runUcJson<{ planned: Array<{ disposition: string }> }>(
      ["verify", "--repo", ".", "--row", "probe.core.fam", "--dry-run"],
      { cwd: tokenless.dir, env: tokenless.env }
    );
    expect(envelope.data.planned.every((p) => p.disposition === "blocked")).toBe(true);
  });
});
//: @use-case:end lifecycle.signals.variant_fanout#blackbox

//: @use-case:lifecycle.signals.errors_hand_back_the_cure#blackbox
describe("lifecycle.signals.errors_hand_back_the_cure", () => {
  /** A workspace where the row was renamed in BOTH the matrix and the marker. */
  function renamedWorkspace(oldId: string, newId: string): Workspace {
    const workspace = makeMultiRowWorkspace({ rows: [oldId] });
    const featurePath = join(workspace.dir, "use-cases", "probe.yml");
    writeFileSync(
      featurePath,
      readFileSync(featurePath, "utf8").replaceAll(`probe.core.${oldId}`, `probe.core.${newId}`)
    );
    const sourcePath = join(workspace.dir, "src", `${oldId}.ts`);
    writeFileSync(
      sourcePath,
      readFileSync(sourcePath, "utf8").replaceAll(`probe.core.${oldId}`, `probe.core.${newId}`)
    );
    return workspace;
  }

  // golden_rename. Both halves of the break name the rename, and following the
  // remediation exactly leaves the matrix clean.
  test("both halves name the rename, and the remediation actually works", () => {
    const workspace = renamedWorkspace("oldname", "newname");
    const human = runUc(["scan", "--repo", "."], { cwd: workspace.dir, env: workspace.env }).stdout;

    expect(human, "the orphaned registration names what it became").toContain("renamed to probe.core.newname");
    expect(human, "the new marker names what it came from").toContain("renamed from probe.core.oldname");
    // Truthful about the append-only registry: release BEFORE re-registering,
    // because bind fails closed while the stale registration stands.
    expect(human).toContain("uc unbind --row probe.core.oldname --reason row_renamed");
    expect(human).toContain("--register-existing");

    const unbind = runUcJson(
      ["unbind", "--repo", ".", "--row", "probe.core.oldname", "--reason", "row_renamed"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(unbind.envelope.ok, `unbind failed: ${unbind.stderr}`).toBe(true);
    const rebind = runUcJson(
      ["bind", "--repo", ".", "--row", "probe.core.newname", "--file", "src/oldname.ts", "--register-existing"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(rebind.envelope.ok, `re-register failed: ${rebind.stderr}`).toBe(true);

    const { envelope } = runUcJson<{ status: { integrity_errors: unknown[] } }>(
      ["scan", "--repo", "."],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(
      envelope.data.status.integrity_errors,
      "following the remediation exactly must leave zero integrity errors"
    ).toHaveLength(0);
  });

  // edge_errors_reach_the_human_output. An agent reading the default output
  // must not be left thinking the matrix is clean.
  test("integrity errors appear in the human output, not only in JSON", () => {
    const workspace = renamedWorkspace("oldname", "newname");
    const human = runUc(["scan", "--repo", "."], { cwd: workspace.dir, env: workspace.env });
    expect(human.stdout).toContain("integrity errors");
    expect(human.stdout).toContain("REGISTRY_ROW_MISSING");
    expect(human.status, "a broken registry must not exit 0").not.toBe(0);
  });

  // bad_unrelated_marker_is_not_blamed. A genuinely new behaviour must not be
  // reported as a rename of an unrelated orphan — a guess offered as a fact is
  // worse than no guess.
  test("an unrelated orphaned registration is not blamed on a rename", () => {
    const workspace = renamedWorkspace("alpha", "somethingcompletelydifferent");
    const human = runUc(["scan", "--repo", "."], { cwd: workspace.dir, env: workspace.env }).stdout;
    expect(human).toContain("REGISTRY_ROW_MISSING");
    expect(human, "dissimilar ids must not be asserted as a rename").not.toContain(
      "renamed to probe.core.somethingcompletelydifferent"
    );
  });
});
//: @use-case:end lifecycle.signals.errors_hand_back_the_cure#blackbox
