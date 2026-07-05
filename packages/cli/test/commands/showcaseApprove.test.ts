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
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { approveRunCommand } from "../../src/commands/approveRun.js";
import {
  showcaseApproveCommand,
  showcaseRequestApprovalCommand,
  showcaseStatusCommand
} from "../../src/commands/showcase.js";
import { renderEnvelope } from "../../src/render.js";
import {
  appendShowcaseEpoch,
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
const OPERATOR_KEY = ed25519Pem();
const AGENT_KEY = ed25519Pem();
const ROGUE_KEY = ed25519Pem();
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
        key_id: "operator-key-1",
        algorithm: "ed25519",
        public_key: OPERATOR_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        assurance_tier: "same_channel_operator_confirmation"
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

function trustedKey(keyId: string, publicKey: string): Keyring["keys"][number] {
  return {
    key_id: keyId,
    algorithm: "ed25519",
    public_key: publicKey,
    valid_from: "2026-01-01T00:00:00Z",
    valid_until: null,
    status: "active",
    assurance_tier: "trusted_host_user_presence"
  };
}

function keyringWith(keys: Keyring["keys"]): Keyring {
  return {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys
  };
}

let workspaceRoot: string;

function fixtureWorkspace(name: string): string {
  const root = mkdtempSync(join(tmpdir(), "ucm-b1-"));
  cpSync(join(fixturesRoot, name), root, { recursive: true });
  return root;
}

function setApprovalPolicyMinimumTier(tier: string): void {
  const path = join(workspaceRoot, "use-cases/showcase-live.yml");
  const text = readFileSync(path, "utf8");
  writeFileSync(
    path,
    text.replace(
      "    approval_policy:\n      mode: predefined\n",
      `    approval_policy:\n      mode: predefined\n      minimum_assurance_tier: ${tier}\n`
    ),
    "utf8"
  );
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

// Build a finished run whose plan REQUIRES user approval but that did NOT end in a
// clean pass: the item's verdict is staled by an epoch change, so the run_outcome
// is "incomplete". The run is still finishable (no unresolved failures), so an
// approval CAN be recorded — yet the run itself did not pass, and the CLI must
// NOT report approving it as an unqualified exit-0 success (exit parity + honesty).
function completeIncompleteRun(suffix = "inc"): string {
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
    idempotencyKey: `bf-${suffix}-start`,
    recordedAt: "2026-06-25T12:00:00.000Z"
  });
  const observation = appendShowcaseObservation({
    context: ctx,
    runId: started.run_id,
    planItemId,
    text: "The live behaviour matched, then the environment changed.",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `bf-${suffix}-observe`,
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
    idempotencyKey: `bf-${suffix}-verdict`,
    recordedAt: "2026-06-25T12:02:00.000Z"
  });
  // An epoch change stales the passing verdict -> run_outcome becomes "incomplete"
  // (the item is no longer current) while leaving no unresolved failures to block
  // finish.
  appendShowcaseEpoch({
    context: ctx,
    runId: started.run_id,
    reason: "Environment changed under the run.",
    staleItemIds: [planItemId],
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `bf-${suffix}-epoch`,
    recordedAt: "2026-06-25T12:02:30.000Z"
  });
  finishShowcaseRun({
    context: ctx,
    runId: started.run_id,
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `bf-${suffix}-finish`,
    recordedAt: "2026-06-25T12:03:00.000Z"
  });
  return started.run_id;
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

// Build a run with enough ledger state to have a plan binding, but no finish
// event yet. Approval requests must refuse this because no one can sign a stable
// finished-run binding.
function unfinishedRun(suffix = "unfinished"): string {
  const ctx = context();
  const plan = planFor(ctx);
  const started = startShowcaseRun({
    context: ctx,
    plan,
    controlMode: "agent_led",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: `b1-${suffix}-start`,
    recordedAt: "2026-06-25T12:00:00.000Z"
  });
  return started.run_id;
}

// Sign a genuine token bound to the LIVE run with the out-of-scope trusted key.
function humanSignsFor(runId: string, keyId = "human-key-1", privateKeyPem = HUMAN_KEY.privateKeyPem): ApprovalToken {
  const binding = computeRunApprovalBinding({ context: context(), runId });
  const request = mintApprovalRequest({ binding, nowMs: Date.now(), ttlMinutes: 15 });
  return signApprovalToken({ request, decision: "approved", privateKey: privateKeyPem, keyId });
}

function approveRunSignsFor(runId: string, decision: ApprovalToken["decision"] = "approved"): ApprovalToken {
  const request = showcaseRequestApprovalCommand.handler({
    argv: ["showcase", "request-approval", "--run", runId, "--repo", workspaceRoot],
    json: true,
    flags: { run: runId }
  });
  expect(request.exitCode).toBe(0);

  const requestPath = join(workspaceRoot, `approval-request-${decision}.json`);
  writeFileSync(requestPath, `${JSON.stringify(request.envelope, null, 2)}\n`, "utf8");
  const privateKeyPath = writePrivateKey();
  const signed = approveRunCommand.handler({
    argv: [
      "approve-run",
      "--request",
      requestPath,
      "--key-file",
      privateKeyPath,
      "--key-id",
      "human-key-1",
      "--decision",
      decision
    ],
    json: true,
    flags: { request: requestPath, keyFile: privateKeyPath, keyId: "human-key-1", decision }
  });
  expect(signed.exitCode).toBe(0);
  const token = (signed.envelope as { data?: { approval_token?: ApprovalToken } }).data?.approval_token;
  if (!token) {
    throw new Error(`no approval_token in envelope: ${JSON.stringify(signed.envelope)}`);
  }
  return token;
}

function writeToken(token: ApprovalToken): string {
  const path = join(workspaceRoot, "approval-token.json");
  writeFileSync(path, `${JSON.stringify(token, null, 2)}\n`, "utf8");
  return path;
}

function writeKeyring(value: Keyring = keyring(), name = "keyring.json"): string {
  const path = join(workspaceRoot, name);
  writeFileSync(path, JSON.stringify(value, null, 2), "utf8");
  return path;
}

function pinApprovalTrustToKeyring(value: Keyring, name = "approval-keyring.json"): string {
  const path = writeKeyring(value, name);
  const configPath = join(workspaceRoot, "use-cases.yml");
  const text = readFileSync(configPath, "utf8");
  writeFileSync(
    configPath,
    `${text.trimEnd()}\napproval_trust:\n  keyring_path: ${name}\n`,
    "utf8"
  );
  return path;
}

function writePublicKey(): string {
  const path = join(workspaceRoot, "human.pub");
  writeFileSync(path, HUMAN_KEY.publicKeyPem, "utf8");
  return path;
}

function writePrivateKey(): string {
  const path = join(workspaceRoot, "human.key");
  writeFileSync(path, HUMAN_KEY.privateKeyPem, "utf8");
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

function recordedDecision(runId: string, eventType: "approval_recorded" | "approval_rejected" = "approval_recorded"): string {
  const ledger = readFileSync(join(workspaceRoot, "showcase-runs", runId, "events.jsonl"), "utf8");
  const events = ledger
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as { event_type?: string; payload?: { decision?: string } })
    .filter((event) => event.event_type === eventType);
  const event = events[events.length - 1];
  if (!event?.payload?.decision) {
    throw new Error(`no ${eventType} decision in ledger for ${runId}`);
  }
  return event.payload.decision;
}

beforeEach(() => {
  workspaceRoot = fixtureWorkspace("evidence-basic");
});
afterEach(() => {
  // best-effort; tmpdir is cleaned by the OS
});

describe("BLOCKER 1 — showcase approve --approval-token: trusted submit path", () => {
  test("request-approval mints a raw approve-run-compatible ucase-approval-request-v1 for a finished run", () => {
    const runId = completePassingRun();
    const result = showcaseRequestApprovalCommand.handler({
      argv: ["showcase", "request-approval", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: { run: runId }
    });

    expect(result.exitCode).toBe(0);
    const request = result.envelope as ReturnType<typeof mintApprovalRequest>;
    expect(request.approval_request_schema).toBe("ucase-approval-request-v1");
    expect(request.binding).toEqual(computeRunApprovalBinding({ context: context(), runId }));
    expect(request.binding.run_id).toBe(runId);
    expect(request.jti).toMatch(/^approval\./);
    expect(Date.parse(request.exp)).toBeGreaterThan(Date.parse(request.iat));

    const requestPath = join(workspaceRoot, "approval-request.json");
    const privateKeyPath = writePrivateKey();
    writeFileSync(requestPath, `${JSON.stringify(request, null, 2)}\n`, "utf8");
    const signed = approveRunCommand.handler({
      argv: ["approve-run", "--request", requestPath, "--key-file", privateKeyPath, "--key-id", "human-key-1"],
      json: true,
      flags: { request: requestPath, keyFile: privateKeyPath, keyId: "human-key-1" }
    });
    expect(signed.exitCode).toBe(0);
    expect((signed.envelope as { data?: { approval_token?: ApprovalToken } }).data?.approval_token?.binding).toEqual(request.binding);
  });

  test("request-approval human view summarizes the unsigned request without signing it", () => {
    const runId = completePassingRun();
    const result = showcaseRequestApprovalCommand.handler({
      argv: ["showcase", "request-approval", "--run", runId, "--repo", workspaceRoot],
      json: false,
      flags: { run: runId }
    });

    const text = renderEnvelope(result.envelope, false);
    expect(text).toContain("approval request");
    expect(text).toContain(`run ${runId}`);
    expect(text).toContain("uc approve-run --request");
    expect(text).not.toContain("approval_token_schema");
  });

  test("request-approval refuses a missing run id and an unfinished run binding", () => {
    const missing = showcaseRequestApprovalCommand.handler({
      argv: ["showcase", "request-approval", "--repo", workspaceRoot],
      json: true,
      flags: {}
    });
    expect(missing.exitCode).toBe(2);
    expect((missing.envelope as { diagnostics?: Array<{ code?: string }> }).diagnostics?.[0]?.code).toBe("cli_invalid_arguments");

    const runId = unfinishedRun();
    const unfinished = showcaseRequestApprovalCommand.handler({
      argv: ["showcase", "request-approval", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: { run: runId }
    });
    expect(unfinished.exitCode).not.toBe(0);
    expect((unfinished.envelope as { diagnostics?: Array<{ code?: string }> }).diagnostics?.[0]?.code).toBe("showcase.finish_required_for_approval");
  });

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

  test("approval policy minimum_assurance_tier lowers the keyring floor for approve and status", () => {
    setApprovalPolicyMinimumTier("same_channel_operator_confirmation");
    const runId = completePassingRun("same-channel");
    const token = humanSignsFor(runId, "operator-key-1", OPERATOR_KEY.privateKeyPem);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Same-channel sign-off is allowed by this row.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect((result.envelope as { ok?: boolean }).ok).toBe(true);
    expect(approvalState(runId, { keyring: keyringPath })).toBe("approved");
  });

  test("(a) approve-run --decision approved_with_known_gaps records and replays that verified token decision", () => {
    const runId = completePassingRun("known-gaps");
    const token = approveRunSignsFor(runId, "approved_with_known_gaps");
    expect(token.decision).toBe("approved_with_known_gaps");
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Genuine human sign-off with known gaps.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect(recordedDecision(runId)).toBe("approved_with_known_gaps");
    expect(approvalState(runId, { keyring: keyringPath })).toBe("approved_with_known_gaps");
  });

  test("(a) approve-run --decision approved still records and replays approved", () => {
    const runId = completePassingRun("approved-token");
    const token = approveRunSignsFor(runId, "approved");
    expect(token.decision).toBe("approved");
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
    expect(recordedDecision(runId)).toBe("approved");
    expect(approvalState(runId, { keyring: keyringPath })).toBe("approved");
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

  test("pinned approval_trust keyring verifies approve and status without caller-nominated trust flags", () => {
    pinApprovalTrustToKeyring(keyringWith([trustedKey("human-key-1", HUMAN_KEY.publicKeyPem)]));
    const runId = completePassingRun("pinned");
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Pinned workspace trust anchor verified this sign-off.",
        actor: "user",
        approvalToken: tokenPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect(approvalState(runId)).toBe("approved");
  });

  test("pinned approval_trust rejects a non-pinned signer even when --keyring nominates it", () => {
    pinApprovalTrustToKeyring(keyringWith([trustedKey("human-key-1", HUMAN_KEY.publicKeyPem)]));
    const runId = completePassingRun("unpinned");
    const rogueToken = humanSignsFor(runId, "rogue-key-1", ROGUE_KEY.privateKeyPem);
    const tokenPath = writeToken(rogueToken);
    const rogueKeyringPath = writeKeyring(
      keyringWith([trustedKey("rogue-key-1", ROGUE_KEY.publicKeyPem)]),
      "rogue-keyring.json"
    );

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "A caller-supplied rogue keyring must not override workspace trust.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: rogueKeyringPath
      }
    });

    expect(result.exitCode).not.toBe(0);
    expect((result.envelope as { diagnostics?: Array<{ code?: string }> }).diagnostics?.[0]?.code).toBe(
      "showcase.approval_trust_anchor_unpinned"
    );
    expect(approvalState(runId)).toBe("pending");
  });

  test("--keyring can narrow a pinned approval_trust keyring to a pinned subset", () => {
    pinApprovalTrustToKeyring(
      keyringWith([
        trustedKey("human-key-1", HUMAN_KEY.publicKeyPem),
        trustedKey("operator-key-1", OPERATOR_KEY.publicKeyPem)
      ])
    );
    const runId = completePassingRun("narrowed");
    const token = humanSignsFor(runId, "operator-key-1", OPERATOR_KEY.privateKeyPem);
    const tokenPath = writeToken(token);
    const narrowedKeyringPath = writeKeyring(
      keyringWith([trustedKey("operator-key-1", OPERATOR_KEY.publicKeyPem)]),
      "operator-only-keyring.json"
    );

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "A caller can select a pinned subset.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: narrowedKeyringPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect(approvalState(runId, { keyring: narrowedKeyringPath })).toBe("approved");
  });

  test("unpinned approval-token verification keeps flag-based behavior but warns that trust is caller-supplied", () => {
    const runId = completePassingRun("caller-supplied");
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const result = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: {
        run: runId,
        statement: "Legacy caller-supplied trust material remains accepted.",
        actor: "user",
        approvalToken: tokenPath,
        keyring: keyringPath
      }
    });

    expect(result.exitCode).toBe(0);
    expect((result.envelope as { diagnostics?: Array<{ code?: string; severity?: string }> }).diagnostics).toContainEqual(
      expect.objectContaining({
        code: "showcase.approval_trust_anchor_caller_supplied",
        severity: "warning"
      })
    );
    expect(approvalState(runId, { keyring: keyringPath })).toBe("approved");
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

  test("EXIT PARITY — approving a finished-but-INCOMPLETE run does NOT exit 0 (json AND human)", () => {
    const runId = completeIncompleteRun();
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    const flags = {
      run: runId,
      statement: "Signed off despite the failing run.",
      actor: "user",
      approvalToken: tokenPath,
      keyring: keyringPath
    };
    const jsonResult = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags
    });
    const humanResult = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: false,
      flags: { ...flags, idempotencyKey: "cli:approve:parity:human" }
    });
    // The run did not pass, so approve must NOT read as an unqualified success.
    expect(jsonResult.exitCode).not.toBe(0);
    // Parity: the SAME outcome in human mode must have the SAME (non-zero) exit.
    expect(humanResult.exitCode).toBe(jsonResult.exitCode);
    expect(humanResult.exitCode).not.toBe(0);
  });

  test("EXIT PARITY — a genuine passing approval still exits 0 in BOTH modes", () => {
    const runId = completePassingRun();
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();
    const flags = {
      run: runId,
      statement: "Genuine sign-off.",
      actor: "user",
      approvalToken: tokenPath,
      keyring: keyringPath
    };
    const jsonResult = showcaseApproveCommand.handler({
      argv: ["showcase", "approve", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags
    });
    expect(jsonResult.exitCode).toBe(0);
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

  test("status exposes verified approval actor_type and assurance_tier in json and human output", () => {
    const runId = completePassingRun();
    const token = humanSignsFor(runId);
    const tokenPath = writeToken(token);
    const keyringPath = writeKeyring();

    showcaseApproveCommand.handler({
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

    const status = showcaseStatusCommand.handler({
      argv: ["showcase", "status", "--run", runId, "--repo", workspaceRoot, "--keyring", keyringPath],
      json: true,
      flags: { run: runId, keyring: keyringPath }
    });
    expect((status.envelope as { data?: { approval?: unknown } }).data?.approval).toEqual({
      actor_type: "user",
      assurance_tier: "trusted_host_user_presence"
    });

    const text = renderEnvelope(status.envelope, false);
    expect(text).toContain("approved by user · tier trusted_host_user_presence");
  });

  test("status leaves unapproved runs without approval actor metadata", () => {
    const runId = completePassingRun();
    const status = showcaseStatusCommand.handler({
      argv: ["showcase", "status", "--run", runId, "--repo", workspaceRoot],
      json: true,
      flags: { run: runId }
    });

    const data = (status.envelope as { data?: Record<string, unknown> }).data ?? {};
    expect(data.approval_state).toBe("pending");
    expect(Object.hasOwn(data, "approval")).toBe(false);
    expect(renderEnvelope(status.envelope, false)).not.toContain("approved by");
  });
});
