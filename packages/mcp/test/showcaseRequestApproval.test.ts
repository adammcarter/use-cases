// F3 — showcase_request_approval mints a PLUGIN-owned, single-use approval
// request bound to the live run. An agent/MCP may only REQUEST; the nonce (jti)
// and exp are minted by the plugin, and a human signs the request out-of-band
// with `uc approve-run`. The MCP tool must NOT suggest the spoofable `uc
// showcase approve` path.
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { showcaseRequestApproval } from "../src/toolHandlers.js";
import {
  appendShowcaseObservation,
  appendShowcaseVerdict,
  finishShowcaseRun,
  loadUseCaseMatrix,
  replayEvidence,
  resolveWorkspaceContext,
  selectShowcasePlan,
  startShowcaseRun
} from "@adammcarter/use-cases-core";

const repoRoot = resolve(import.meta.dirname, "../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

let workspaceRoot: string;

beforeEach(() => {
  workspaceRoot = mkdtempSync(join(tmpdir(), "ucm-mcp-f3-"));
  cpSync(join(fixturesRoot, "evidence-basic"), workspaceRoot, { recursive: true });
});
afterEach(() => {
  rmSync(workspaceRoot, { recursive: true, force: true });
});

function completePassingRun(): string {
  const context = resolveWorkspaceContext({ workspaceRoot });
  const planResult = selectShowcasePlan({
    context,
    matrix: loadUseCaseMatrix({ context }),
    evidence: replayEvidence({ context }),
    request: {
      audience: "reviewer",
      timeboxSeconds: 600,
      maxItems: 1,
      hostSurface: "codex.cli",
      generatedAt: "2026-06-25T12:00:00.000Z",
      freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
    }
  });
  if (!planResult.plan) throw new Error("expected fixture plan");
  const started = startShowcaseRun({
    context,
    plan: planResult.plan,
    controlMode: "agent_led",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "mcp-f3-start",
    recordedAt: "2026-06-25T12:00:00.000Z"
  });
  const obs = appendShowcaseObservation({
    context,
    runId: started.run_id,
    planItemId: "item.showcase.live.golden",
    text: "Live behavior matched.",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "mcp-f3-obs",
    recordedAt: "2026-06-25T12:01:00.000Z"
  });
  appendShowcaseVerdict({
    context,
    runId: started.run_id,
    planItemId: "item.showcase.live.golden",
    verdict: "pass",
    observationEventIds: [obs.event.event_id],
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "mcp-f3-verdict",
    recordedAt: "2026-06-25T12:02:00.000Z"
  });
  finishShowcaseRun({
    context,
    runId: started.run_id,
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "mcp-f3-finish",
    recordedAt: "2026-06-25T12:03:00.000Z"
  });
  return started.run_id;
}

describe("showcase_request_approval — F3 plugin-minted request", () => {
  test("emits a single-use ucase-approval-request-v1 bound to the run + the approve-run signer command", () => {
    const runId = completePassingRun();
    const result = showcaseRequestApproval({ repo: workspaceRoot, run: runId }) as {
      data: {
        approval_request: { approval_request_schema: string; jti: string; iat: string; exp: string; binding: { run_id: string } } | null;
        approval_request_schema: string | null;
        suggested_signer_command: string[] | null;
      };
    };
    const request = result.data.approval_request;
    expect(request).not.toBeNull();
    expect(request?.approval_request_schema).toBe("ucase-approval-request-v1");
    expect(request?.binding.run_id).toBe(runId);
    // Nonce is present and exp is strictly after iat (single-use, time-boxed).
    expect(request?.jti).toBeTruthy();
    expect(Date.parse(request!.exp)).toBeGreaterThan(Date.parse(request!.iat));
    // The signer command points at approve-run, NOT the spoofable showcase approve.
    expect(result.data.suggested_signer_command).toContain("approve-run");
    expect(result.data.suggested_signer_command).not.toContain("approve");
  });

  test("two requests mint DISTINCT nonces (each is single-use)", () => {
    const runId = completePassingRun();
    const a = showcaseRequestApproval({ repo: workspaceRoot, run: runId }) as { data: { approval_request: { jti: string } } };
    const b = showcaseRequestApproval({ repo: workspaceRoot, run: runId }) as { data: { approval_request: { jti: string } } };
    expect(a.data.approval_request.jti).not.toBe(b.data.approval_request.jti);
  });
});
