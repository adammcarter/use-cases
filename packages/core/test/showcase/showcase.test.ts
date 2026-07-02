import { appendFileSync, cpSync, existsSync, mkdtempSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/roots.js";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import { replayEvidence } from "../../src/evidence/index.js";
import { computePresentationPlanHash, selectShowcasePlan, type PresentationPlan } from "../../src/presentation/index.js";
import {
  appendShowcaseApproval,
  appendShowcaseFailureDecision,
  appendShowcaseEpoch,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  correctShowcaseVerdict,
  finishShowcaseRun,
  readShowcaseEvents,
  replayShowcaseRun,
  startShowcaseRun
} from "../../src/showcase/index.js";

const repoRoot = resolve(import.meta.dirname, "../../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

describe("P6 showcase run replay", () => {
  test("run_started only derives prepared_not_performed and writes no summary file", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);

    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-start-only",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const status = replayShowcaseRun({ context, runId: started.run_id });

    expect(status).toMatchObject({
      schema_version: 1,
      run_id: started.run_id,
      complete: true,
      execution_status: "prepared_not_performed",
      run_outcome: "prepared_not_performed",
      approval_state: "pending"
    });
    expect(summaryFiles(workspaceRoot)).toEqual([]);
  });

  test("failed verdict without a failure decision prevents ordinary finish", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-fail-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const observation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: "The live behavior was visible but wrong.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-fail-observe",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });
    appendShowcaseVerdict({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      verdict: "fail",
      observationEventIds: [observation.event.event_id],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-fail-verdict",
      recordedAt: "2026-06-25T12:02:00.000Z"
    });

    expect(() =>
      finishShowcaseRun({
        context,
        runId: started.run_id,
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: "p6-fail-finish",
        recordedAt: "2026-06-25T12:03:00.000Z"
      })
    ).toThrow(/failure decision/i);
    expect(replayShowcaseRun({ context, runId: started.run_id })).toMatchObject({
      run_outcome: "failed",
      execution_status: "running",
      unresolved_failure_count: 1
    });
  });

  test("agent actor cannot record approval for a user-required plan", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const run = completePassingRun(context);

    expect(() =>
      appendShowcaseApproval({
        context,
        runId: run.run_id,
        decision: "approved",
        actorType: "agent",
        hostSurface: "codex.cli",
        statement: "Agent cannot approve for user.",
        idempotencyKey: "p6-agent-approval",
        recordedAt: "2026-06-25T12:05:00.000Z"
      })
    ).toThrow(/user-required approval/i);
  });

  test("untrusted raw user approval event does not satisfy pending user approval", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const run = completePassingRun(context);
    const ledgerPath = join(workspaceRoot, "showcase-runs", run.run_id, "events.jsonl");

    appendFileSync(
      ledgerPath,
      `${JSON.stringify({
        schema_version: 1,
        event_type: "approval_recorded",
        event_id: "evt_untrusted_user_approval",
        run_id: run.run_id,
        aggregate_id: run.run_id,
        sequence: 5,
        recorded_at: "2026-06-25T12:04:00.000Z",
        actor_type: "user",
        host_surface: "codex.cli",
        idempotency_key: "raw:approval:user",
        intent_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        payload: {
          decision: "approved",
          approver: { type: "user" },
          capture_method: "command_handler",
          approval_statement: "Raw JSONL cannot stand in for a trusted user prompt.",
          scope: {
            plan_content_hash: run.event.payload.plan_content_hash,
            run_outcome: "passed"
          }
        }
      })}\n`
    );

    const status = replayShowcaseRun({ context, runId: run.run_id });
    expect(status.approval_state).toBe("pending");
    expect(status.diagnostic_summary).toMatchObject({
      ignored_approval_events: ["evt_untrusted_user_approval"]
    });
  });

  test("untrusted raw user rejection event does not satisfy pending user approval", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const run = completePassingRun(context);
    const ledgerPath = join(workspaceRoot, "showcase-runs", run.run_id, "events.jsonl");

    appendFileSync(
      ledgerPath,
      `${JSON.stringify({
        schema_version: 1,
        event_type: "approval_rejected",
        event_id: "evt_untrusted_user_rejection",
        run_id: run.run_id,
        aggregate_id: run.run_id,
        sequence: 5,
        recorded_at: "2026-06-25T12:04:00.000Z",
        actor_type: "user",
        host_surface: "codex.cli",
        idempotency_key: "raw:rejection:user",
        intent_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        payload: {
          decision: "rejected",
          approver: { type: "user" },
          capture_method: "command_handler",
          rejection_statement: "Raw JSONL cannot stand in for a trusted user prompt."
        }
      })}\n`
    );

    const status = replayShowcaseRun({ context, runId: run.run_id });
    expect(status.approval_state).toBe("pending");
    expect(status.diagnostic_summary).toMatchObject({
      ignored_approval_events: ["evt_untrusted_user_rejection"]
    });
  });

  test("trusted user approval requires a finished run and binds to the finish event", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const unfinished = startShowcaseRun({
      context,
      plan: planFor(context),
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-unfinished-approval-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });

    expect(() =>
      appendShowcaseApproval({
        context,
        runId: unfinished.run_id,
        decision: "approved",
        actorType: "user",
        hostSurface: "codex.cli",
        statement: "Trusted approval still requires finish.",
        idempotencyKey: "p6-unfinished-approval",
        recordedAt: "2026-06-25T12:01:00.000Z",
        authority: { kind: "trusted_host_token", token: "test-token", verified: true }
      })
    ).toThrow(/finish/i);

    const finished = completePassingRun(context);
    const finishEvent = readShowcaseEvents(context, finished.run_id).events.find((event) => event.event_type === "run_finished");
    const approval = appendShowcaseApproval({
      context,
      runId: finished.run_id,
      decision: "approved",
      actorType: "user",
      hostSurface: "codex.cli",
      statement: "Trusted user accepted the finished run.",
      idempotencyKey: "p6-finished-approval",
      recordedAt: "2026-06-25T12:04:00.000Z",
      authority: { kind: "trusted_host_token", token: "test-token", verified: true }
    });

    expect(approval.event.payload.scope).toMatchObject({
      plan_content_hash: finished.event.payload.plan_content_hash,
      finish_event_id: finishEvent?.event_id,
      run_outcome: "passed"
    });
    expect(approval.status.approval_state).toBe("approved");
  });

  test("revision epoch stales previous verdicts until they are rerun or carried forward", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const run = completePassingRun(context);

    appendShowcaseEpoch({
      context,
      runId: run.run_id,
      reason: "workspace_changed",
      staleItemIds: ["item.showcase.live.golden"],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-epoch",
      recordedAt: "2026-06-25T12:06:00.000Z"
    });

    const status = replayShowcaseRun({ context, runId: run.run_id });
    expect(status.items[0]).toMatchObject({
      plan_item_id: "item.showcase.live.golden",
      item_currency: "stale_due_to_epoch_change",
      verification_state: "stale"
    });
    expect(status.approval_state).toBe("pending");
  });

  test("verdict correction appends a new event and changes derived status", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-correct-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const observation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: "The live behavior was visible.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-correct-observe",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });
    const verdict = appendShowcaseVerdict({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      verdict: "fail",
      observationEventIds: [observation.event.event_id],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-correct-verdict",
      recordedAt: "2026-06-25T12:02:00.000Z"
    });

    correctShowcaseVerdict({
      context,
      runId: started.run_id,
      targetEventId: verdict.event.event_id,
      correctedVerdict: "pass",
      reason: "Mistaken verdict entry.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-correct-verdict-head",
      recordedAt: "2026-06-25T12:03:00.000Z"
    });

    const status = replayShowcaseRun({ context, runId: started.run_id });
    expect(status.items[0]).toMatchObject({
      verdict: "pass",
      item_currency: "corrected"
    });
    expect(readFileSync(join(workspaceRoot, "showcase-runs", started.run_id, "events.jsonl"), "utf8")).toContain(
      "verdict_corrected"
    );
  });

  test("verdict correction only resolves the targeted failure in a multi-item run", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planWithTwoItems(planFor(context));
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const firstObservation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: "First item failed.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-observe-1",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });
    const secondObservation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.secondary",
      text: "Second item failed.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-observe-2",
      recordedAt: "2026-06-25T12:01:30.000Z"
    });
    const firstVerdict = appendShowcaseVerdict({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      verdict: "fail",
      observationEventIds: [firstObservation.event.event_id],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-verdict-1",
      recordedAt: "2026-06-25T12:02:00.000Z"
    });
    appendShowcaseVerdict({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.secondary",
      verdict: "fail",
      observationEventIds: [secondObservation.event.event_id],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-verdict-2",
      recordedAt: "2026-06-25T12:02:30.000Z"
    });

    correctShowcaseVerdict({
      context,
      runId: started.run_id,
      targetEventId: firstVerdict.event.event_id,
      correctedVerdict: "pass",
      reason: "First item was entered incorrectly.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-multi-correct-1",
      recordedAt: "2026-06-25T12:03:00.000Z"
    });

    const status = replayShowcaseRun({ context, runId: started.run_id });
    expect(status.unresolved_failure_count).toBe(1);
    expect(status.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ plan_item_id: "item.showcase.live.golden", verdict: "pass" }),
        expect.objectContaining({ plan_item_id: "item.showcase.live.secondary", verdict: "fail" })
      ])
    );
  });

  test("waive failure decision derives passed_with_waivers rather than ordinary pass", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-waive-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const observation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: "The issue is accepted as out of scope.",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-waive-observe",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });
    const verdict = appendShowcaseVerdict({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      verdict: "fail",
      observationEventIds: [observation.event.event_id],
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-waive-verdict",
      recordedAt: "2026-06-25T12:02:00.000Z"
    });
    appendShowcaseFailureDecision({
      context,
      runId: started.run_id,
      verdictEventId: verdict.event.event_id,
      decision: "waive_with_reason",
      reason: "Known gap accepted for this demo.",
      actorType: "user",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-waive-decision",
      recordedAt: "2026-06-25T12:02:30.000Z"
    });
    finishShowcaseRun({
      context,
      runId: started.run_id,
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-waive-finish",
      recordedAt: "2026-06-25T12:03:00.000Z"
    });

    const status = replayShowcaseRun({ context, runId: started.run_id });
    expect(status).toMatchObject({
      run_outcome: "passed_with_waivers",
      unresolved_failure_count: 0
    });
    expect(status.items[0]).toMatchObject({
      verdict: "waived",
      verification_state: "not_required"
    });
  });

  test("a secret in an observation is stored redacted in the showcase ledger", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-redact-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const leaky = "Logged in with sk-ABCD1234efgh5678 and api_key=SUPERSECRETVALUE shown.";
    const observation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: leaky,
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-redact-observe",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });

    const stored = readShowcaseEvents(context, started.run_id).events.find(
      (event) => event.event_id === observation.event.event_id
    );
    expect(stored?.payload.observation).toBe(
      "Logged in with sk-[redacted] and api_key=[redacted] shown."
    );
    // The raw secret must not survive anywhere on disk.
    const ledgerPath = join(workspaceRoot, "showcase-runs", started.run_id, "events.jsonl");
    const raw = readFileSync(ledgerPath, "utf8");
    expect(raw).not.toContain("sk-ABCD1234efgh5678");
    expect(raw).not.toContain("SUPERSECRETVALUE");
  });

  test("a clean observation with no secret pattern is stored verbatim", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const plan = planFor(context);
    const started = startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-clean-start",
      recordedAt: "2026-06-25T12:00:00.000Z"
    });
    const prose = "The api documentation explains how tokens and secrets work in general.";
    const observation = appendShowcaseObservation({
      context,
      runId: started.run_id,
      planItemId: "item.showcase.live.golden",
      text: prose,
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: "p6-clean-observe",
      recordedAt: "2026-06-25T12:01:00.000Z"
    });
    const stored = readShowcaseEvents(context, started.run_id).events.find(
      (event) => event.event_id === observation.event.event_id
    );
    expect(stored?.payload.observation).toBe(prose);
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-${name}-`));
  cpSync(join(fixturesRoot, name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function planFor(context: ReturnType<typeof resolveWorkspaceContext>) {
  const result = selectShowcasePlan({
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
  if (!result.plan) {
    throw new Error("expected fixture plan");
  }
  return result.plan;
}

function completePassingRun(context: ReturnType<typeof resolveWorkspaceContext>) {
  const started = startShowcaseRun({
    context,
    plan: planFor(context),
    controlMode: "agent_led",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "p6-pass-start",
    recordedAt: "2026-06-25T12:00:00.000Z"
  });
  const observation = appendShowcaseObservation({
    context,
    runId: started.run_id,
    planItemId: "item.showcase.live.golden",
    text: "The live behavior matched the expected outcome.",
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "p6-pass-observe",
    recordedAt: "2026-06-25T12:01:00.000Z"
  });
  appendShowcaseVerdict({
    context,
    runId: started.run_id,
    planItemId: "item.showcase.live.golden",
    verdict: "pass",
    observationEventIds: [observation.event.event_id],
    actorType: "user",
    hostSurface: "codex.cli",
    idempotencyKey: "p6-pass-verdict",
    recordedAt: "2026-06-25T12:02:00.000Z"
  });
  finishShowcaseRun({
    context,
    runId: started.run_id,
    actorType: "agent",
    hostSurface: "codex.cli",
    idempotencyKey: "p6-pass-finish",
    recordedAt: "2026-06-25T12:03:00.000Z"
  });
  return started;
}

function summaryFiles(workspaceRoot: string): string[] {
  const root = join(workspaceRoot, "showcase-runs");
  if (!existsSync(root)) {
    return [];
  }
  return readdirSync(root, { recursive: true })
    .map((entry) => String(entry))
    .filter((entry) => /summary\\.(ya?ml|json)$/.test(entry));
}

function planWithTwoItems(plan: PresentationPlan): PresentationPlan {
  const secondItem = {
    ...plan.selected_items[0],
    plan_item_id: "item.showcase.live.secondary",
    use_case_id: "showcase.live.secondary",
    scenario_ids: ["showcase.live.secondary.cli"]
  };
  const withoutHash = {
    ...plan,
    sections: plan.sections.map((section) => ({
      ...section,
      item_ids: [...section.item_ids, secondItem.plan_item_id]
    })),
    selected_items: [...plan.selected_items, secondItem],
    plan_content_hash: ""
  };
  return {
    ...withoutHash,
    plan_content_hash: computePresentationPlanHash(withoutHash)
  };
}
