import { existsSync } from "node:fs";
import { computeSemanticHash } from "../schema/index.js";
import { PresentationSkillsError } from "../errors.js";
import { computePresentationPlanHash, type PresentationPlan } from "../presentation/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { HostSurface } from "../useCases/types.js";
import { appendShowcaseEventLine, readShowcaseEvents, showcaseLedgerPath } from "./jsonlLedger.js";
import { replayShowcaseEvents, replayShowcaseRun } from "./replayRun.js";
import type {
  ShowcaseActorType,
  ShowcaseAppendResult,
  ShowcaseControlMode,
  ShowcaseEvent,
  ShowcaseStartOptions,
  ShowcaseVerdict
} from "./types.js";

export function startShowcaseRun(options: ShowcaseStartOptions): ShowcaseAppendResult {
  if (computePresentationPlanHash(options.plan) !== options.plan.plan_content_hash) {
    throw new PresentationSkillsError("Plan content hash does not match plan body.", "showcase_plan_hash_mismatch");
  }
  if (options.plan.integrity_acknowledgement_required && !options.knownGapAcknowledgement?.acknowledged) {
    throw new PresentationSkillsError("Partial plan requires known-gap acknowledgement.", "showcase_known_gap_ack_required");
  }
  const runId = runIdFrom(options.idempotencyKey, options.recordedAt);
  const ledgerPath = showcaseLedgerPath(options.context, runId);
  const payload = {
    plan: options.plan,
    plan_content_hash: options.plan.plan_content_hash,
    control_mode: options.controlMode,
    initial_epoch_id: "epoch.1",
    known_gap_acknowledgement: options.knownGapAcknowledgement ?? null
  };
  const existing = readShowcaseEvents(options.context, runId);
  if (!existing.complete && existsSync(ledgerPath)) {
    throw new PresentationSkillsError("Refusing to start against damaged showcase history.", "showcase_ledger_damaged");
  }
  const existingEvent = existing.events.find((event) => event.idempotency_key === options.idempotencyKey);
  const intentDigest = intentDigestFor("run_started", payload, options.actorType, options.hostSurface);
  if (existingEvent) {
    if (existingEvent.intent_digest === intentDigest) {
      return appendResult(options.context, existingEvent);
    }
    throw new PresentationSkillsError("Idempotency key was reused with different intent.", "showcase_idempotency_conflict");
  }
  if (existing.events.length > 0) {
    throw new PresentationSkillsError("Showcase run id already exists.", "showcase_run_id_conflict");
  }
  const event = makeEvent({
    context: options.context,
    runId,
    eventType: "run_started",
    sequence: 1,
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload
  });
  appendShowcaseEventLine(options.context, event);
  return appendResult(options.context, event);
}

export function appendShowcaseObservation(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  planItemId: string;
  text: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "observation_recorded",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      plan_item_id: options.planItemId,
      epoch_id: "epoch.1",
      observation: options.text
    }
  });
  return appendResult(options.context, event);
}

export function appendShowcaseVerdict(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  planItemId: string;
  verdict: ShowcaseVerdict;
  observationEventIds: string[];
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const read = readShowcaseEvents(options.context, options.runId);
  const observations = new Set(
    read.events
      .filter((event) => event.event_type === "observation_recorded" && event.payload.plan_item_id === options.planItemId)
      .map((event) => event.event_id)
  );
  if (!options.observationEventIds.some((eventId) => observations.has(eventId))) {
    throw new PresentationSkillsError("Verdict requires a prior observation.", "showcase_verdict_requires_observation");
  }
  const event = appendEvent(options.context, options.runId, {
    eventType: "verdict_recorded",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      plan_item_id: options.planItemId,
      epoch_id: "epoch.1",
      observation_event_ids: options.observationEventIds,
      verdict: options.verdict,
      verifier: { type: options.actorType }
    }
  });
  return appendResult(options.context, event);
}

export function appendShowcaseFailureDecision(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  verdictEventId: string;
  decision: "continue" | "pause_to_fix" | "waive_with_reason" | "abort";
  reason: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const read = readShowcaseEvents(options.context, options.runId);
  const target = read.events.find((event) => event.event_id === options.verdictEventId);
  if (!target || (target.event_type !== "verdict_recorded" && target.event_type !== "verdict_corrected")) {
    throw new PresentationSkillsError("Failure decision target must be a verdict event.", "showcase_invalid_failure_decision_target");
  }
  const targetVerdict =
    target.event_type === "verdict_recorded" ? target.payload.verdict : target.payload.corrected_verdict;
  if (targetVerdict !== "fail" && targetVerdict !== "blocked") {
    throw new PresentationSkillsError("Failure decision target must be a failed or blocked verdict.", "showcase_invalid_failure_decision_target");
  }
  const event = appendEvent(options.context, options.runId, {
    eventType: "failure_decision_recorded",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      verdict_event_id: options.verdictEventId,
      decision: options.decision,
      reason: options.reason
    }
  });
  return appendResult(options.context, event);
}

export function pauseShowcaseRun(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  reason: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "run_paused",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      reason: options.reason
    }
  });
  return appendResult(options.context, event);
}

export function resumeShowcaseRun(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  reason: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "run_resumed",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      reason: options.reason
    }
  });
  return appendResult(options.context, event);
}

export function appendShowcaseEpoch(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  reason: "workspace_changed";
  staleItemIds: string[];
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "epoch_started",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      previous_epoch_id: "epoch.1",
      epoch_id: "epoch.2",
      reason: options.reason,
      stale_item_ids: options.staleItemIds,
      staling_strategy: "all_prior_verdicts"
    }
  });
  return appendResult(options.context, event);
}

export function finishShowcaseRun(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const status = replayShowcaseRun({ context: options.context, runId: options.runId });
  if (status.unresolved_failure_count > 0) {
    throw new PresentationSkillsError("Cannot finish until each failed or blocked verdict has a failure decision.", "showcase_failure_decision_required");
  }
  const event = appendEvent(options.context, options.runId, {
    eventType: "run_finished",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      requested_finish: true
    }
  });
  return appendResult(options.context, event);
}

export function appendShowcaseApproval(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  decision: "approved" | "approved_with_known_gaps";
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  statement: string;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const read = readShowcaseEvents(options.context, options.runId);
  const start = read.events.find((event) => event.event_type === "run_started");
  const plan = start?.payload.plan as PresentationPlan | undefined;
  if (options.actorType !== "user" && planRequiresUserApproval(plan)) {
    throw new PresentationSkillsError("Agent cannot record user-required approval.", "showcase.user_required_approval");
  }
  const event = appendEvent(options.context, options.runId, {
    eventType: "approval_recorded",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      decision: options.decision,
      approver: { type: options.actorType },
      capture_method: options.actorType === "user" ? "trusted_user_interactive_cli" : "command_handler",
      approval_statement: options.statement,
      scope: {
        plan_content_hash: plan?.plan_content_hash ?? "",
        run_outcome: replayShowcaseRun({ context: options.context, runId: options.runId }).run_outcome
      }
    }
  });
  return appendResult(options.context, event);
}

export function rejectShowcaseApproval(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  statement: string;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "approval_rejected",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      decision: "rejected",
      approver: { type: options.actorType },
      capture_method: options.actorType === "user" ? "trusted_user_interactive_cli" : "command_handler",
      rejection_statement: options.statement
    }
  });
  return appendResult(options.context, event);
}

export function correctShowcaseVerdict(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  targetEventId: string;
  correctedVerdict: ShowcaseVerdict;
  reason: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const read = readShowcaseEvents(options.context, options.runId);
  const target = read.events.find((event) => event.event_id === options.targetEventId);
  if (!target || target.event_type !== "verdict_recorded") {
    throw new PresentationSkillsError("Correction target must be a verdict event.", "showcase_invalid_correction_target");
  }
  const event = appendEvent(options.context, options.runId, {
    eventType: "verdict_corrected",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      target_event_id: options.targetEventId,
      plan_item_id: target.payload.plan_item_id,
      corrected_verdict: options.correctedVerdict,
      reason: options.reason
    }
  });
  return appendResult(options.context, event);
}

function appendEvent(
  context: ResolvedWorkspaceContext,
  runId: string,
  options: {
    eventType: ShowcaseEvent["event_type"];
    actorType: ShowcaseActorType;
    hostSurface: HostSurface;
    idempotencyKey: string;
    recordedAt?: string;
    payload: Record<string, unknown>;
  }
): ShowcaseEvent {
  const read = readShowcaseEvents(context, runId);
  if (!read.complete) {
    throw new PresentationSkillsError("Refusing to append to damaged showcase history.", "showcase_ledger_damaged");
  }
  const existing = read.events.find((event) => event.idempotency_key === options.idempotencyKey);
  const intentDigest = intentDigestFor(options.eventType, options.payload, options.actorType, options.hostSurface);
  if (existing) {
    if (existing.intent_digest === intentDigest) {
      return existing;
    }
    throw new PresentationSkillsError("Idempotency key was reused with different intent.", "showcase_idempotency_conflict");
  }
  const event = makeEvent({
    context,
    runId,
    eventType: options.eventType,
    sequence: read.events.length + 1,
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: options.payload
  });
  appendShowcaseEventLine(context, event);
  return event;
}

function makeEvent(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  eventType: ShowcaseEvent["event_type"];
  sequence: number;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
  payload: Record<string, unknown>;
}): ShowcaseEvent {
  const recordedAt = options.recordedAt ?? new Date().toISOString();
  const eventId = `evt.${options.runId}.${options.sequence}`;
  return {
    schema_version: 1,
    event_type: options.eventType,
    event_id: eventId,
    run_id: options.runId,
    aggregate_id: options.runId,
    sequence: options.sequence,
    recorded_at: recordedAt,
    actor_type: options.actorType,
    host_surface: options.hostSurface,
    idempotency_key: options.idempotencyKey,
    intent_digest: intentDigestFor(options.eventType, options.payload, options.actorType, options.hostSurface),
    payload: options.payload
  };
}

function appendResult(context: ResolvedWorkspaceContext, event: ShowcaseEvent): ShowcaseAppendResult {
  return {
    schema_version: 1,
    run_id: event.run_id,
    appended_event_ids: [event.event_id],
    event,
    status: replayShowcaseEvents(event.run_id, readShowcaseEvents(context, event.run_id).events)
  };
}

function runIdFrom(idempotencyKey: string, recordedAt?: string): string {
  const base = sanitizeId(idempotencyKey || recordedAt || new Date().toISOString());
  return `run.${base}`;
}

function sanitizeId(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "showcase";
}

function intentDigestFor(
  eventType: ShowcaseEvent["event_type"],
  payload: Record<string, unknown>,
  actorType: ShowcaseActorType,
  hostSurface: HostSurface
): string {
  return computeSemanticHash({ eventType, payload, actorType, hostSurface });
}

function planRequiresUserApproval(plan: PresentationPlan | undefined): boolean {
  return (plan?.selected_items ?? []).some(
    (item) =>
      item.approval_policy_snapshot.mode === "predefined" &&
      Array.isArray(item.approval_policy_snapshot.requirements) &&
      item.approval_policy_snapshot.requirements.some((requirement) => requirement.approver_type === "user")
  );
}
