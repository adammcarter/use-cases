// BLOCKER 1 (F3) — `uc showcase approve` must have a TRUSTED submit path.
//
// `approve-run` mints a signed approval token, but until this change NO command
// ingested it: `showcase approve` hard-coded untrusted_automation and never
// passed the token to the verify+append core. So a real human did request+sign
// and then hit a dead end — a user-required run stayed approval_state:pending
// forever, and the signed-token verify/append core was unreachable dead code.
//
// These tests exercise the SHIPPED CLI surface end-to-end over the real append
// core: they build a genuine run, sign a genuine token with a keyring key, then
// drive `showcaseApproveCommand.handler` with `--approval-token` + the trusted
// key material and assert `showcaseStatusCommand.handler` reads approved. The
// negatives prove F3 stayed intact: every spoof exits NON-ZERO and stays pending.
import { generateKeyPairSync } from "node:crypto";
import { cpSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import {
  showcaseApproveCommand,
  showcaseStatusCommand
} from "../../src/commands/showcase.js";
import {
  appendShowcaseObservation,
  appendShowcaseVerdict,
  computeRunApprovalBinding,
  finishShowcaseRun,
  loadUseCaseMatrix,
  mintApprovalRequest,
  replayEvidence,
  resolveWorkspaceContext,
  selectShowcasePlan,
  signApprovalToken,
  startShowcaseRun,
  type ApprovalToken,
  type Keyring
} from "@adammcarter/use-cases-core";

const repoRoot = resolve(import.meta.dirname, "../../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

function ed25519Pem() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString()
  };
}

const HUMAN_KEY = ed25519Pem();
const AGENT_KEY = ed25519Pem();
// The CLI verifies a token against the REAL wall clock (a human signs and submits
// within the TTL). So a genuine, unexpired token is minted at "now"; the expired
// negative below deliberately signs in the distant past.

function keyring(): Keyring {
  return {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      {
        key_id: "human-key-1",
        algorithm: "ed25519",
        public_key: HUMAN_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        assurance_tier: "trusted_host_user_presence"
      },
      {
        key_id: "agent-key-1",
        algorithm: "ed25519",
        public_key: AGENT_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        assurance_tier: "untrusted_automation"
      }
    ]
  };
}

let workspaceRoot: string;

function fixtureWorkspace(name: string): string {
  const root = mkdtempSync(join(tmpdir(), "ucm-b1-"));
  cpSync(join(fixturesRoot, name), root, { recursive: true });
  return root;
}

function context() {
  return resolveWorkspaceContext({ workspaceRoot });
}

function planFor(ctx: ReturnType<typeof resolveWorkspaceContext>) {
  const result = selectShowcasePlan({
    context: ctx,
    matrix: loadUseCaseMatrix({ context: ctx }),
    evidence: replayEvidence({ context: ctx }),
    request: {
      audience: "reviewer",
      timeboxSeconds: 600,
      maxItems: 1,
      hostSurface: "codex.cli",
      generatedAt: "2026-06-25T12:00:00.000Z",
      freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
    }
  });
  if (!result.plan) {
    throw new Error("expected fixture plan");
  }
  return result.plan;
}

// Build a completed, passing run whose plan REQUIRES user approval, returning the
// run id + the first plan item id (discovered from the plan, never hard-coded).
// `suffix` distinguishes runs so two runs in one test get distinct run ids +
// bindings (as real, separately-driven runs would).
function completePassingRun(suffix = "one"): string {
  const ctx = context();
  const plan = planFor(ctx);
  const planItemId = plan.selected_items[0]?.plan_item_id;
  if (!planItemId) {
    throw new Error("expected a plan item");
  }
  const started = startShowcaseRun({
    context: ctx,
    plan,
    controlMode: "agent_led",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `b1-${suffix}-start`,
    recordedAt: "2026-06-25T12:00:00.000Z"
  });
  const observation = appendShowcaseObservation({
    context: ctx,
    runId: started.run_id,
    planItemId,
    text: "The live behaviour matched the expected outcome.",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `b1-${suffix}-observe`,
    recordedAt: "2026-06-25T12:01:00.000Z"
  });
  appendShowcaseVerdict({
    context: ctx,
    runId: started.run_id,
    planItemId,
    verdict: "pass",
    observationEventIds: [observation.event.event_id],
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `b1-${suffix}-verdict`,
    recordedAt: "2026-06-25T12:02:00.000Z"
  });
  finishShowcaseRun({
    context: ctx,
    runId: started.run_id,
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `b1-${suffix}-finish`,
    recordedAt: "2026-06-25T12:03:00.000Z"
  });
  return started.run_id;
}

// Sign a genuine token bound to the LIVE run with the out-of-scope trusted key.
function humanSignsFor(runId: string, keyId = "human-key-1", privateKeyPem = HUMAN_KEY.privateKeyPem): ApprovalToken {
  const binding = computeRunApprovalBinding({ context: context(), runId });
  const request = mintApprovalRequest({ binding, nowMs: Date.now(), ttlMinutes: 15 });
  return signApprovalToken({ request, decision: "approved", privateKey: privateKeyPem, keyId });
}

function writeToken(token: ApprovalToken): string {
  const path = join(workspaceRoot, "approval-token.json");
  writeFileSync(path, `${JSON.stringify(token, null, 2)}\n`, "utf8");
  return path;
}

function writeKeyring(): string {
  const path = join(workspaceRoot, "keyring.json");
  writeFileSync(path, JSON.stringify(keyring(), null, 2), "utf8");
  return path;
}

function writePublicKey(): string {
  const path = join(workspaceRoot, "human.pub");
  writeFileSync(path, HUMAN_KEY.publicKeyPem, "utf8");
  return path;
}

// Read the approval state as `showcase status` reports it. A trust flag
// (keyring/publicKey) is REQUIRED to verify an embedded signed token — without
// it, status fails closed (a signed approval reads pending). The trust flags
// mirror what a human would pass on the real CLI.
function approvalState(runId: string, trustFlags: Record<string, string> = {}): string {
  const status = showcaseStatusCommand.handler({
    argv: ["showcase", "status", "--run", runId, "--repo", workspaceRoot],
    json: true,
    flags: { run: runId, ...trustFlags }
  });
  return (status.envelope as { data?: { approval_state?: string } }).data?.approval_state ?? "(missing)";
}

beforeEach(() => {
  workspaceRoot = fixtureWorkspace("evidence-basic");
});
afterEach(() => {
  // best-effort; tmpdir is cleaned by the OS
});

describe("BLOCKER 1 — showcase approve --approval-token: trusted submit path", () => {
  test("(a) request -> approve-run signs a keyring token -> approve --approval-token --keyring -> status approved", () => {
    const runId = completePassingRun();
    // Precondition: a user-required run starts pending.
    expect(approvalState(runId)).toBe("pending");

    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Genuine human sign-off.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect((result.envelope as { ok?: boolean }).ok).toBe(true);
    expect(approvalState(runId, { keyring: keyringPath })).toBe("approved");
    // Fail-closed: status WITHOUT the trusted key material still reads pending.
    expect(approvalState(runId)).toBe("pending");
  });

  test("(a) the single --public-key form also verifies a genuine token -> approved", () => {
    const runId = completePassingRun();
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const pubPath = writePublicKey();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Genuine human sign-off via single public key.",
        actor: "user",
        approvalToken: tokenPath,
        publicKey: pubPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect(approvalState(runId, { publicKey: pubPath })).toBe("approved");
  });

  test("(b) NO token on a user-required plan -> rejected NON-ZERO, stays pending", () => {
    const runId = completePassingRun();
    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: { run: runId, statement: "No token.", actor: "user" }
    });
    expect(result.exitCode).not.toBe(0);
    expect(approvalState(runId)).toBe("pending");
  });

  test("(b) a wrong-run token -> rejected NON-ZERO, stays pending", () => {
    const runIdA = completePassingRun("A");
    const tokenForA = humanSignsFor(runIdA);
    const runIdB = completePassingRun("B");
    const tokenPath = writeToken(tokenForA);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runIdB, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runIdB,
        statement: "Token for run A cannot approve run B.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });
    expect(result.exitCode).not.toBe(0);
    expect(approvalState(runIdB)).toBe("pending");
  });

  test("(b) an expired token -> rejected NON-ZERO, stays pending", () => {
    const runId = completePassingRun();
    // Sign with an iat far in the past so the 15m TTL is blown by now.
    const binding = computeRunApprovalBinding({ context: context(), runId });
    const request = mintApprovalRequest({ binding, nowMs: Date.parse("2020-01-01T00:00:00.000Z"), ttlMinutes: 15 });
    const token = signApprovalToken({ request, decision: "approved", privateKey: HUMAN_KEY.privateKeyPem, keyId: "human-key-1" });
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Expired token.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });
    expect(result.exitCode).not.toBe(0);
    expect(approvalState(runId)).toBe("pending");
  });

  test("(b) a forged token (agent key claiming the human key_id) -> rejected NON-ZERO, stays pending", () => {
    const runId = completePassingRun();
    // AGENT key signs but claims the trusted human key_id.
    const forged = humanSignsFor(runId, "human-key-1", AGENT_KEY.privateKeyPem);
    const tokenPath = writeToken(forged);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Forged signature.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });
    expect(result.exitCode).not.toBe(0);
    expect(approvalState(runId)).toBe("pending");
  });

  test("(b) an agent self-approve attempt (untrusted_automation-tier token) -> rejected NON-ZERO, stays pending", () => {
    const runId = completePassingRun();
    // A token signed by the automation-tier key is NOT a human sign-off.
    const agentToken = humanSignsFor(runId, "agent-key-1", AGENT_KEY.privateKeyPem);
    const tokenPath = writeToken(agentToken);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Automation tier is not human sign-off.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });
    expect(result.exitCode).not.toBe(0);
    expect(approvalState(runId)).toBe("pending");
  });
});
