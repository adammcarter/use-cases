// The black-box oracle for showcase/flow.yml.
//
// Everything here talks ONLY to the CLI binary: no core import, no internal
// call, no whitebox helper. Each test builds its own throwaway workspace, so
// nothing depends on a fixture a later change might reshape. UC_RUN_KEY_FILE
// always points at a throwaway path inside the temp dir, so no test reads or
// writes the developer's own machine key.
//
// One finding surfaced while writing this file: `showcase.flow.revision_epoch_
// staleness` names a real core capability (appendShowcaseEpoch, and replayRun
// understands epoch_started events) but NO CLI command appends one. `showcase
// resume` takes only --run/--reason/--actor; there is no --changed-path, no
// `mark-stale`, nothing that diffs the workspace and stales a verdict. That
// entire row is left as test.todo below rather than faked — see the comment
// on that describe block for the exact evidence.
//
// A second, smaller finding: `showcase start` always records control_mode
// agent_led (packages/cli/src/commands/showcase.ts hardcodes it in both the
// --plan-file and --adhoc branches) and `record-observation` always records
// actor agent (no --actor flag on that command). Only `record-verdict`'s
// --actor varies who is credited. So "choose the control mode for each item:
// agent, user, script or mixed" (control_modes.golden_mixed's first step) is
// only reachable at the verdict layer through this binary — the tests below
// prove what IS reachable rather than what the row's prose implies is.
import { generateKeyPairSync } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

// A row with `verification_policy.mode: none` is not selectable for a plan
// (measured: it yields an empty selection), so every fixture row below carries
// a real requirements policy — mode: requirements, evidence_kind: live_demo,
// required_verifiers: [user] — exactly as showcase rows are meant to.
const REQUIRE_USER_APPROVAL = `    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: User accepts the demonstrated showcase scope.`;

const NO_APPROVAL = `    approval_policy:
      mode: none`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function singleRowFeatureFile(approvalPolicyBlock: string): string {
  return `schema_version: 1
feature:
  id: probe.showcase
  name: Probe showcase
  summary: A behaviour proved live through showcase start/observe/verdict/finish.
use_cases:
  - id: probe.showcase.thing
    title: The thing works
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Prove one scenario end to end through a live showcase run.
    preconditions: [A source file exists.]
    trigger: An agent demonstrates the behaviour live.
    scenarios:
      - id: probe.showcase.thing.golden_runs
        kind: steps
        steps: [Run it live.]
        observable_outcomes: [It works.]
    observable_outcomes: [The row is demonstrated live.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
${approvalPolicyBlock}
`;
}

function makeWorkspace(approvalPolicyBlock: string = NO_APPROVAL): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-showcase-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), singleRowFeatureFile(approvalPolicyBlock));
  return { dir, env };
}

/** The v1 status shape `showcase status` returns at `data` directly (not `data.status`). */
interface RunStatus {
  run_id: string;
  complete: boolean;
  execution_status: string;
  run_outcome: string;
  approval_state: string;
  unresolved_failure_count: number;
  approval?: { actor_type: string; assurance_tier: string };
  items: Array<{
    plan_item_id: string;
    verdict: string;
    item_currency: string;
    verification_state: string;
    latest_observation_event_id: string | null;
    latest_verdict_event_id: string | null;
  }>;
  diagnostic_summary?: { ignored_approval_events?: string[] };
}

/** Every mutating verb (start/observe/verdict/decide/correct/finish/approve) wraps its
 * derived RunStatus at `data.status`, alongside the one event it just appended. */
interface ShowcaseActionData {
  run_id: string;
  event: { event_id: string; payload: Record<string, unknown> };
  status: RunStatus;
}

function start(workspace: Workspace, key: string, useCaseId = "probe.showcase.thing") {
  return runUcJson<ShowcaseActionData>(
    ["showcase", "start", "--repo", ".", "--adhoc", "--select", useCaseId, "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

function observe(workspace: Workspace, runId: string, itemId: string, text: string, key: string) {
  return runUcJson<ShowcaseActionData>(
    ["showcase", "record-observation", "--repo", ".", "--run", runId, "--item", itemId, "--text", text, "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

function verdict(workspace: Workspace, runId: string, itemId: string, verdictValue: string, key: string, actor?: string) {
  const args = ["showcase", "record-verdict", "--repo", ".", "--run", runId, "--item", itemId, "--verdict", verdictValue, "--idempotency-key", key];
  if (actor) args.push("--actor", actor);
  return runUcJson<ShowcaseActionData>(args, { cwd: workspace.dir, env: workspace.env });
}

function decide(workspace: Workspace, runId: string, verdictEventId: string, decision: string, reason: string, key: string) {
  return runUcJson<ShowcaseActionData>(
    ["showcase", "decide", "--repo", ".", "--run", runId, "--verdict-event", verdictEventId, "--decision", decision, "--reason", reason, "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

function correct(workspace: Workspace, runId: string, targetEventId: string, verdictValue: string, reason: string, key: string) {
  return runUcJson<ShowcaseActionData>(
    ["showcase", "correct", "--repo", ".", "--run", runId, "--target-event", targetEventId, "--verdict", verdictValue, "--reason", reason, "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
}

function finish(workspace: Workspace, runId: string) {
  return runUcJson<ShowcaseActionData>(["showcase", "finish", "--repo", ".", "--run", runId], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

function status(workspace: Workspace, runId: string, extra: string[] = []) {
  return runUcJson<RunStatus>(["showcase", "status", "--repo", ".", "--run", runId, ...extra], {
    cwd: workspace.dir,
    env: workspace.env
  });
}

function runDir(workspace: Workspace, runId: string): string {
  return join(workspace.dir, "showcase-runs", runId);
}

function eventsPath(workspace: Workspace, runId: string): string {
  return join(runDir(workspace, runId), "events.jsonl");
}

function readEvents(workspace: Workspace, runId: string): Array<Record<string, unknown>> {
  return readFileSync(eventsPath(workspace, runId), "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as Record<string, unknown>);
}

//: @use-case:showcase.flow.live_acceptance_flow#blackbox
describe("showcase.flow.live_acceptance_flow", () => {
  // golden_cli. The claim under test is "derived from events, not a summary
  // anyone wrote": prove it by reading status TWICE off the same ledger (a
  // cached/written summary could drift between reads; a replay cannot) and by
  // showing the run directory holds nothing but the ledger itself.
  test("start, observe, pass a verdict, finish, and read status twice off the same ledger", () => {
    const workspace = makeWorkspace();
    const started = start(workspace, "start");
    expect(started.envelope.ok).toBe(true);
    const runId = started.envelope.data.run_id;

    expect(observe(workspace, runId, "item.probe.showcase.thing", "Watched the feature run live.", "obs").envelope.ok).toBe(true);
    expect(verdict(workspace, runId, "item.probe.showcase.thing", "pass", "verdict").envelope.ok).toBe(true);
    expect(finish(workspace, runId).envelope.ok).toBe(true);

    expect(
      readdirSync(runDir(workspace, runId)),
      "the run directory must hold only the ledger, no summary file"
    ).toEqual(["events.jsonl"]);

    const firstRead = status(workspace, runId).envelope.data;
    const secondRead = status(workspace, runId).envelope.data;
    expect(firstRead).toEqual(secondRead);
    expect(firstRead.execution_status).toBe("completed");
    expect(firstRead.run_outcome).toBe("passed");
    expect(firstRead.items[0].verification_state).toBe("requirements_met");
  });

  // bad_started_is_not_performed.
  test("a started run derives prepared_not_performed and writes no summary file", () => {
    const workspace = makeWorkspace();
    const runId = start(workspace, "start-only").envelope.data.run_id;

    expect(readdirSync(runDir(workspace, runId))).toEqual(["events.jsonl"]);
    const read = status(workspace, runId).envelope.data;
    expect(read.execution_status).toBe("prepared_not_performed");
    expect(read.run_outcome).toBe("prepared_not_performed");
  });

  // edge_approval_binds_to_the_finish_event.
  test("trusted approval requires a finished run and binds to the finish event", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = start(workspace, "bind-start").envelope.data.run_id;

    // Before finish: refused outright. There is no finish event yet for a
    // binding to name.
    const early = runUc(["showcase", "request-approval", "--repo", ".", "--run", runId, "--json"], {
      cwd: workspace.dir,
      env: workspace.env
    });
    const earlyBody = JSON.parse(early.stdout) as { ok: boolean; diagnostics: Array<{ code: string }> };
    expect(earlyBody.ok).toBe(false);
    expect(earlyBody.diagnostics.map((d) => d.code)).toContain("showcase.finish_required_for_approval");

    observe(workspace, runId, "item.probe.showcase.thing", "obs", "bind-obs");
    verdict(workspace, runId, "item.probe.showcase.thing", "pass", "bind-verdict");
    const finished = finish(workspace, runId);
    const finishEventId = finished.envelope.data.event.event_id;

    // Absent until an approval event exists.
    expect(status(workspace, runId).envelope.data.approval_state).toBe("pending");

    const afterFinish = runUc(["showcase", "request-approval", "--repo", ".", "--run", runId, "--json"], {
      cwd: workspace.dir,
      env: workspace.env
    });
    const request = JSON.parse(afterFinish.stdout) as { binding: { finish_event_id: string } };
    expect(request.binding.finish_event_id, "the approval binding must name the finish event").toBe(finishEventId);
  });
});
//: @use-case:end showcase.flow.live_acceptance_flow#blackbox

/** Drive one item through observation + a passing verdict recorded under `actor`. */
function performUnderActor(actor: string, seed: string) {
  const workspace = makeWorkspace();
  const runId = start(workspace, `${seed}-start`).envelope.data.run_id;
  observe(workspace, runId, "item.probe.showcase.thing", "obs", `${seed}-obs`);
  const recorded = verdict(workspace, runId, "item.probe.showcase.thing", "pass", `${seed}-verdict`, actor);
  const verdictEvent = readEvents(workspace, runId).find((e) => e.event_type === "verdict_recorded") as {
    payload: { verifier: { type: string } };
  };
  return { recorded, verdictEvent, status: status(workspace, runId).envelope.data };
}

//: @use-case:showcase.flow.control_modes#blackbox
describe("showcase.flow.control_modes", () => {
  // golden_mixed. "Mixed" is reachable through the binary only at the verdict
  // layer (see the file header comment) — this proves that layer: the actor
  // that drove each verdict is the one the ledger names.
  test("the actor driving each verdict is recorded on the event, whichever mode drove it", () => {
    for (const actor of ["agent", "user", "script"]) {
      const { recorded, verdictEvent } = performUnderActor(actor, actor);
      expect(recorded.envelope.ok).toBe(true);
      expect(verdictEvent.payload.verifier.type).toBe(actor);
    }
  });

  // bad_agent_led_run_cannot_claim_user_approval.
  test("an agent actor recording approval for a user-required plan is refused", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = start(workspace, "agent-claim-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "agent-claim-obs");
    verdict(workspace, runId, "item.probe.showcase.thing", "pass", "agent-claim-verdict");
    finish(workspace, runId);

    // No --actor (defaults to agent) and no --approval-token.
    const claimed = runUcJson(
      ["showcase", "approve", "--repo", ".", "--run", runId, "--statement", "I approve my own demo."],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(claimed.envelope.ok).toBe(false);
    expect(JSON.stringify(claimed.envelope.diagnostics)).toContain("showcase.user_required_approval");
    expect(status(workspace, runId).envelope.data.approval_state).toBe("pending");
  });

  // edge_proof_semantics_do_not_change_with_the_driver.
  test("the derived status is identical whichever actor drove the same item", () => {
    const byActor = ["agent", "user", "script"].map((actor) => performUnderActor(actor, `sem-${actor}`).status);
    for (const s of byActor) {
      expect(s.run_outcome).toBe("passed");
      expect(s.items[0].verdict).toBe("pass");
      expect(s.items[0].verification_state).toBe("requirements_met");
    }
  });
});
//: @use-case:end showcase.flow.control_modes#blackbox

/** A two-row fixture, needed only by the correction test below: `showcase start
 * --adhoc` selects exactly one item (--select takes a single id), so a run with
 * more than one item has to go through `plan showcase` -> a plan file. */
function multiItemFeatureFile(): string {
  const row = (id: string, title: string): string => `  - id: probe.showcase.${id}
    title: ${title}
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Prove ${id}.
    preconditions: [A source file exists.]
    trigger: An agent demonstrates the behaviour live.
    scenarios:
      - id: probe.showcase.${id}.golden_runs
        kind: steps
        steps: [Run it live.]
        observable_outcomes: [It works.]
    observable_outcomes: [The row is demonstrated live.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
    approval_policy:
      mode: none
`;
  return `schema_version: 1
feature:
  id: probe.showcase
  name: Probe showcase
  summary: Two rows so one run can carry two independent failures.
use_cases:
${row("alpha", "Alpha works")}${row("beta", "Beta works")}`;
}

function makeMultiItemWorkspace(): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-blackbox-showcase-multi-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), multiItemFeatureFile());
  return { dir, env };
}

function startFromPlan(workspace: Workspace, key: string): string {
  const planned = runUcJson<{ plan: Record<string, unknown> }>(["plan", "showcase", "--repo", "."], {
    cwd: workspace.dir,
    env: workspace.env
  });
  expect(planned.envelope.ok, "plan showcase must select both rows").toBe(true);
  writeFileSync(join(workspace.dir, "plan.json"), JSON.stringify(planned.envelope.data.plan));
  const startResult = runUcJson<ShowcaseActionData>(
    ["showcase", "start", "--repo", ".", "--plan-file", "plan.json", "--idempotency-key", key],
    { cwd: workspace.dir, env: workspace.env }
  );
  expect(startResult.envelope.ok, `start from plan failed: ${startResult.stderr}`).toBe(true);
  return startResult.envelope.data.run_id;
}

//: @use-case:showcase.flow.failure_decisions#blackbox
describe("showcase.flow.failure_decisions", () => {
  // golden_branch. "continue" is the branch that proves failed items are not
  // silently skipped: it clears the finish gate, but the failing verdict —
  // and therefore run_outcome:failed — stays exactly as recorded. Deciding to
  // continue is not deciding the failure did not happen.
  test("deciding to continue past a failure clears the finish gate without hiding the failure", () => {
    const workspace = makeWorkspace();
    const runId = start(workspace, "branch-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "branch-obs");
    const failed = verdict(workspace, runId, "item.probe.showcase.thing", "fail", "branch-verdict");
    const verdictEventId = failed.envelope.data.event.event_id;

    const decided = decide(workspace, runId, verdictEventId, "continue", "known issue, tracked separately", "branch-decide");
    expect(decided.envelope.ok).toBe(true);
    expect(decided.envelope.data.status.unresolved_failure_count).toBe(0);

    const finished = finish(workspace, runId);
    expect(finished.envelope.ok, "the failure decision must clear the finish gate").toBe(true);
    expect(finished.envelope.data.status.execution_status).toBe("completed");
    expect(finished.envelope.data.status.run_outcome, "continuing past a failure must not launder it into a pass").toBe("failed");
    expect(finished.envelope.data.status.items[0].verdict).toBe("fail");
  });

  // bad_failed_verdict_without_a_decision.
  test("finishing with a failed verdict and no failure decision is refused", () => {
    const workspace = makeWorkspace();
    const runId = start(workspace, "nodecision-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "nodecision-obs");
    verdict(workspace, runId, "item.probe.showcase.thing", "fail", "nodecision-verdict");

    const finished = finish(workspace, runId);
    expect(finished.envelope.ok).toBe(false);
    expect(JSON.stringify(finished.envelope.diagnostics)).toContain("showcase_failure_decision_required");
  });

  // edge_waiver_is_not_an_ordinary_pass.
  test("waiving a failed item derives passed_with_waivers, never an ordinary pass", () => {
    const workspace = makeWorkspace();
    const runId = start(workspace, "waive-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "waive-obs");
    const failed = verdict(workspace, runId, "item.probe.showcase.thing", "fail", "waive-verdict");
    const verdictEventId = failed.envelope.data.event.event_id;

    decide(workspace, runId, verdictEventId, "waive_with_reason", "known flaky demo environment", "waive-decide");
    const finished = finish(workspace, runId);
    expect(finished.envelope.ok).toBe(true);
    expect(finished.envelope.data.status.run_outcome).toBe("passed_with_waivers");
    expect(finished.envelope.data.status.run_outcome).not.toBe("passed");
    expect(finished.envelope.data.status.items[0].verdict).toBe("waived");
  });

  // edge_correction_resolves_only_the_targeted_failure.
  test("correcting one failing item in a multi-item run leaves the other failure untouched", () => {
    const workspace = makeMultiItemWorkspace();
    const runId = startFromPlan(workspace, "multi-start");
    observe(workspace, runId, "item.probe.showcase.alpha", "obs alpha", "alpha-obs");
    observe(workspace, runId, "item.probe.showcase.beta", "obs beta", "beta-obs");
    const alphaVerdict = verdict(workspace, runId, "item.probe.showcase.alpha", "fail", "alpha-verdict");
    verdict(workspace, runId, "item.probe.showcase.beta", "fail", "beta-verdict");
    const alphaEventId = alphaVerdict.envelope.data.event.event_id;

    const corrected = correct(workspace, runId, alphaEventId, "pass", "retested, alpha actually passed", "alpha-correct");
    expect(corrected.envelope.ok).toBe(true);
    const finalStatus = corrected.envelope.data.status;
    expect(finalStatus.unresolved_failure_count, "correcting alpha must resolve only alpha's failure").toBe(1);

    const alphaItem = finalStatus.items.find((i) => i.plan_item_id === "item.probe.showcase.alpha")!;
    const betaItem = finalStatus.items.find((i) => i.plan_item_id === "item.probe.showcase.beta")!;
    expect(alphaItem.verdict).toBe("pass");
    expect(alphaItem.item_currency).toBe("corrected");
    expect(betaItem.verdict, "correcting alpha must never touch beta").toBe("fail");
    expect(betaItem.item_currency).toBe("current");
  });
});
//: @use-case:end showcase.flow.failure_decisions#blackbox

// The core has appendShowcaseEpoch (packages/core/src/showcase/appendShowcaseEvent.ts,
// which replayRun.ts understands: an epoch_started event marks named items'
// item_currency "stale_due_to_epoch_change"), but NO CLI command appends one.
// `uc showcase resume` (packages/cli/src/commands/showcase.ts) accepts only
// --run/--reason/--actor/--idempotency-key/--recorded-at — no --changed-path,
// no revision snapshot, nothing that diffs the workspace — and its handler
// calls only resumeShowcaseRun, never appendShowcaseEpoch. `rg -n "epoch" -i
// packages/cli/src` returns no hits at all. Every scenario in this row needs a
// CLI affordance that does not exist, so none of the three can be driven
// through the binary honestly.
// NOT bound to this row on purpose. The core has the machinery — appendShowcaseEpoch
// in showcase/appendShowcaseEvent.ts, and replayRun setting item_currency
// "stale_due_to_epoch_change" — but NO CLI command ever calls it: `uc showcase
// resume` takes no revision input and never appends an epoch event. So the
// behaviour is real and unobservable from outside, which is a contract gap to
// raise rather than a test to fake. Binding this row would mark it verified
// against an oracle that asserts nothing.
describe("showcase.flow.revision_epoch_staleness", () => {
  test.todo(
    "golden_resume — resuming across a revision change marks affected verdicts stale: no CLI command appends an epoch_started event (appendShowcaseEpoch is core-only, unreachable from `uc showcase resume`)"
  );
  test.todo(
    "bad_old_verdicts_never_stay_silently_current — same missing affordance: staling verdicts on a changed input has no CLI trigger"
  );
  test.todo(
    "edge_stale_verdicts_are_rerun_or_carried_forward — same missing affordance: nothing can produce a stale verdict through the CLI to rerun or carry forward"
  );
});

function ed25519Pem(): { publicKeyPem: string; privateKeyPem: string } {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString()
  };
}

function writeKeyring(workspace: Workspace, keyId: string, publicKeyPem: string): string {
  const path = join(workspace.dir, "keyring.json");
  writeFileSync(
    path,
    JSON.stringify({
      keyring_schema_id: "ucase-public-key-registry-v1",
      keys: [
        {
          key_id: keyId,
          algorithm: "ed25519",
          public_key: publicKeyPem,
          valid_from: "2026-01-01T00:00:00Z",
          valid_until: null,
          status: "active",
          max_assurance_tier: "trusted_host_user_presence"
        }
      ]
    })
  );
  return path;
}

/** The trusted human sign-off path in full: `request-approval` mints an
 * UNSIGNED request (the MCP/agent half); `approve-run` — run in the human's
 * OWN shell against a key the agent never sees — is the only thing that can
 * turn it into a signed token. */
function signTrustedApproval(
  workspace: Workspace,
  runId: string,
  key: { publicKeyPem: string; privateKeyPem: string },
  keyId: string
): { tokenPath: string; keyringPath: string } {
  const requestRaw = runUc(["showcase", "request-approval", "--repo", ".", "--run", runId, "--json"], {
    cwd: workspace.dir,
    env: workspace.env
  });
  const requestPath = join(workspace.dir, "approval-request.json");
  writeFileSync(requestPath, requestRaw.stdout);

  const keyFilePath = join(workspace.dir, "human.key.pem");
  writeFileSync(keyFilePath, key.privateKeyPem);
  const tokenPath = join(workspace.dir, "approval-token.json");
  const signed = runUcJson(
    ["approve-run", "--request", requestPath, "--key-file", keyFilePath, "--key-id", keyId,
      "--decision", "approved", "--assurance-method", "os_presence", "--out", tokenPath],
    { cwd: workspace.dir, env: workspace.env }
  );
  expect(signed.envelope.ok, `approve-run failed: ${signed.stderr}`).toBe(true);

  const keyringPath = writeKeyring(workspace, keyId, key.publicKeyPem);
  return { tokenPath, keyringPath };
}

function finishedApprovalRun(workspace: Workspace, seed: string): string {
  const runId = start(workspace, `${seed}-start`).envelope.data.run_id;
  observe(workspace, runId, "item.probe.showcase.thing", "obs", `${seed}-obs`);
  verdict(workspace, runId, "item.probe.showcase.thing", "pass", `${seed}-verdict`);
  finish(workspace, runId);
  return runId;
}

/** Append a well-formed event straight to the ledger file, bypassing every CLI
 * verb — standing in for anything that is not `uc showcase approve
 * --approval-token` (a hand-edited ledger, a rogue script, an MCP write that
 * skipped the verify+append core). Returns the forged event's id. */
function appendRawEvent(
  workspace: Workspace,
  runId: string,
  partial: { event_type: string; actor_type: string; payload: Record<string, unknown> }
): string {
  const sequence = readEvents(workspace, runId).length + 1;
  const eventId = `evt.forged.${sequence}`;
  const event = {
    schema_version: 1,
    event_type: partial.event_type,
    event_id: eventId,
    run_id: runId,
    aggregate_id: runId,
    sequence,
    recorded_at: "2026-06-25T13:00:00.000Z",
    actor_type: partial.actor_type,
    host_surface: "codex.cli",
    idempotency_key: `forged-${sequence}`,
    intent_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    payload: partial.payload
  };
  writeFileSync(eventsPath(workspace, runId), `${JSON.stringify(event)}\n`, { flag: "a" });
  return eventId;
}

//: @use-case:showcase.flow.approval_authority_boundary#blackbox
describe("showcase.flow.approval_authority_boundary", () => {
  const HUMAN_KEY = ed25519Pem();

  // golden_trusted_confirmation_path.
  test("a signed token from the trusted confirmation path is the only thing that gets appended as a user approval", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = finishedApprovalRun(workspace, "trusted");

    const { tokenPath, keyringPath } = signTrustedApproval(workspace, runId, HUMAN_KEY, "human-key-1");
    const approved = runUcJson<ShowcaseActionData>(
      ["showcase", "approve", "--repo", ".", "--run", runId, "--statement", "User accepts the demonstrated showcase scope.",
        "--approval-token", tokenPath, "--keyring", keyringPath],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(approved.status).toBe(0);
    const payload = approved.envelope.data.event.payload as { capture_method: string; approver: { type: string } };
    // MCP/an agent can only REQUEST approval; this is the proof the write
    // itself came from the signed path, not a caller asserting it.
    expect(payload.capture_method).toBe("host_signed_approval_token");
    expect(payload.approver.type).toBe("user");

    expect(status(workspace, runId, ["--keyring", keyringPath]).envelope.data.approval_state).toBe("approved");
  });

  // bad_untrusted_approval_event.
  test("a raw user approval event appended outside the tool does not satisfy pending approval", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = finishedApprovalRun(workspace, "forged-approve");
    const finishEvent = readEvents(workspace, runId).find((e) => e.event_type === "run_finished") as { event_id: string };

    const forgedId = appendRawEvent(workspace, runId, {
      event_type: "approval_recorded",
      actor_type: "user",
      payload: {
        decision: "approved",
        approver: { type: "user", actor_type: "user", assurance_tier: "trusted_host_user_presence" },
        capture_method: "self_reported",
        approval_statement: "forged approval",
        scope: { plan_content_hash: "sha256:fake", finish_event_id: finishEvent.event_id, run_outcome: "passed", known_gap_count: 0 }
      }
    });

    const read = status(workspace, runId).envelope.data;
    expect(read.approval_state, "an untrusted event must not be honoured as approval").toBe("pending");
    expect(read.diagnostic_summary?.ignored_approval_events, "the ignored forgery must be named, not silently dropped").toContain(forgedId);
  });

  // bad_untrusted_rejection_event. The boundary is not one-directional: a
  // forged rejection is exactly as unauthorized as a forged approval.
  test("a raw user rejection event appended outside the tool does not satisfy pending approval either", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = finishedApprovalRun(workspace, "forged-reject");
    const finishEvent = readEvents(workspace, runId).find((e) => e.event_type === "run_finished") as { event_id: string };

    appendRawEvent(workspace, runId, {
      event_type: "approval_rejected",
      actor_type: "user",
      payload: {
        decision: "rejected",
        approver: { type: "user", actor_type: "user", assurance_tier: "trusted_host_user_presence" },
        capture_method: "self_reported",
        approval_statement: "forged rejection",
        scope: { plan_content_hash: "sha256:fake", finish_event_id: finishEvent.event_id, run_outcome: "passed", known_gap_count: 0 }
      }
    });

    expect(
      status(workspace, runId).envelope.data.approval_state,
      "an untrusted rejection must not be honoured either"
    ).toBe("pending");
  });

  // edge_scripted_approval_leaves_the_ledger_untouched.
  test("a scripted noninteractive user approval is refused and appends nothing to the ledger", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = finishedApprovalRun(workspace, "scripted");
    const before = readEvents(workspace, runId).length;

    const scripted = runUcJson(
      ["showcase", "approve", "--repo", ".", "--run", runId, "--statement", "scripted", "--actor", "user"],
      { cwd: workspace.dir, env: workspace.env }
    );
    expect(scripted.envelope.ok).toBe(false);
    expect(JSON.stringify(scripted.envelope.diagnostics)).toContain("showcase.trusted_user_confirmation_required");
    expect(readEvents(workspace, runId).length, "a refused approval must not mutate the ledger").toBe(before);
  });
});
//: @use-case:end showcase.flow.approval_authority_boundary#blackbox

//: @use-case:showcase.flow.status_separation#blackbox
describe("showcase.flow.status_separation", () => {
  // golden_status. Four axes, four separate fields — none derivable from any
  // of the others, which is this row's whole design point.
  test("verdict, verification, run completion and approval read as four separate fields", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = start(workspace, "sep-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "sep-obs");
    verdict(workspace, runId, "item.probe.showcase.thing", "pass", "sep-verdict");
    finish(workspace, runId);

    const s = status(workspace, runId).envelope.data;
    // Performed (completed) but unapproved (pending) is exactly the state
    // this row exists to make legible.
    expect(s.execution_status).toBe("completed");
    expect(s.run_outcome).toBe("passed");
    expect(s.approval_state).toBe("pending");
    expect(s.items[0].verdict).toBe("pass");
    expect(s.items[0].verification_state).toBe("requirements_met");
  });

  // bad_states_are_never_collapsed.
  test("passing every item with no user approval is never reported as a single pass label", () => {
    const workspace = makeWorkspace(REQUIRE_USER_APPROVAL);
    const runId = start(workspace, "collapse-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "collapse-obs");
    verdict(workspace, runId, "item.probe.showcase.thing", "pass", "collapse-verdict");
    finish(workspace, runId);

    const data = status(workspace, runId).envelope.data;
    expect(data.run_outcome).toBe("passed");
    expect(
      data.approval_state,
      "run_outcome:passed must not be read as acceptance while approval is still pending"
    ).toBe("pending");
    expect(data).not.toHaveProperty("result");
    expect(data).not.toHaveProperty("accepted");
  });

  // edge_correction_changes_the_derived_status. Status is computed fresh from
  // the ledger every call, so correcting a verdict after finish moves it.
  test("correcting a verdict after finish changes the derived status because nothing is cached", () => {
    const workspace = makeWorkspace();
    const runId = start(workspace, "recompute-start").envelope.data.run_id;
    observe(workspace, runId, "item.probe.showcase.thing", "obs", "recompute-obs");
    const passed = verdict(workspace, runId, "item.probe.showcase.thing", "pass", "recompute-verdict");
    const verdictEventId = passed.envelope.data.event.event_id;
    finish(workspace, runId);
    expect(status(workspace, runId).envelope.data.run_outcome).toBe("passed");

    const corrected = correct(workspace, runId, verdictEventId, "fail", "found a defect after the demo", "recompute-correct");
    expect(corrected.envelope.ok).toBe(true);

    const after = status(workspace, runId).envelope.data;
    expect(after.execution_status, "the run stays completed").toBe("completed");
    expect(after.run_outcome, "the outcome must move with the correction").toBe("failed");
    expect(after.unresolved_failure_count).toBe(1);
  });
});
//: @use-case:end showcase.flow.status_separation#blackbox
