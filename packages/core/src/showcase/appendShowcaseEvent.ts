import { existsSync } from "node:fs";
import { computeSemanticHash } from "../schema/index.js";
import { redactSecrets } from "../redact.js";
import { UseCasesPluginError } from "../errors.js";
import type { PresentationPlan } from "../presentation/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { HostSurface } from "../useCases/types.js";
import { appendShowcaseEventLine, readShowcaseEvents, showcaseLedgerPath } from "./jsonlLedger.js";
import { replayShowcaseEvents, replayShowcaseRun, type ReplayTrustOptions } from "./replayRun.js";
import { assertPresentationPlanHash } from "./planBinding.js";
import { computeApprovalBindingFromEvents } from "./approvalBinding.js";
import { verifyApprovalToken, type ApprovalToken } from "./approvalToken.js";
import type { AssuranceTier } from "./approvalTiers.js";
import { approvalAssuranceFloorForPlan } from "./approvalPolicy.js";
import type { PublicKeyResolver } from "../markers/proofSignature.js";
import type { AssuranceTierResolver, WebAuthnCredentialResolver } from "../markers/keyring.js";
import type {
  ShowcaseActorType,
  ShowcaseAppendResult,
  ShowcaseControlMode,
  ShowcaseEvent,
  ShowcaseStartOptions,
  ShowcaseVerdict
} from "./types.js";

export function startShowcaseRun(options: ShowcaseStartOptions): ShowcaseAppendResult {
  assertPresentationPlanHash(options.plan);
  if (options.plan.integrity_acknowledgement_required && !options.knownGapAcknowledgement?.acknowledged) {
    throw new UseCasesPluginError("Partial plan requires known-gap acknowledgement.", "showcase_known_gap_ack_required");
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
    throw new UseCasesPluginError("Refusing to start against damaged showcase history.", "showcase_ledger_damaged");
  }
  const existingEvent = existing.events.find((event) => event.idempotency_key === options.idempotencyKey);
  const intentDigest = intentDigestFor("run_started", payload, options.actorType, options.hostSurface);
  if (existingEvent) {
    if (existingEvent.intent_digest === intentDigest) {
      return appendResult(options.context, existingEvent);
    }
    throw new UseCasesPluginError("Idempotency key was reused with different intent.", "showcase_idempotency_conflict");
  }
  if (existing.events.length > 0) {
    throw new UseCasesPluginError("Showcase run id already exists.", "showcase_run_id_conflict");
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
      // Redact at the point of persistence so the durable ledger never holds a
      // leaked secret. The intent digest is computed over this payload, so it
      // agrees with the redacted stored form.
      observation: redactSecrets(options.text)
    }
  });
  return appendResult(options.context, event);
}

export function appendShowcaseAction(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  planItemId: string;
  action: Record<string, unknown>;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
}): ShowcaseAppendResult {
  const event = appendEvent(options.context, options.runId, {
    eventType: "action_recorded",
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload: {
      plan_item_id: options.planItemId,
      epoch_id: "epoch.1",
      action: options.action
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
    throw new UseCasesPluginError("Verdict requires a prior observation.", "showcase_verdict_requires_observation");
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
    throw new UseCasesPluginError("Failure decision target must be a verdict event.", "showcase_invalid_failure_decision_target");
  }
  const targetVerdict =
    target.event_type === "verdict_recorded" ? target.payload.verdict : target.payload.corrected_verdict;
  if (targetVerdict !== "fail" && targetVerdict !== "blocked") {
    throw new UseCasesPluginError("Failure decision target must be a failed or blocked verdict.", "showcase_invalid_failure_decision_target");
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
    throw new UseCasesPluginError("Cannot finish until each failed or blocked verdict has a failure decision.", "showcase_failure_decision_required");
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

// F3: the resolver/tier/floor a caller (CLI/MCP) supplies from its configured
// keyring so approval trust is computed from the signed token, never asserted.
export interface ApprovalVerificationOptions {
  approvalToken?: ApprovalToken;
  resolver?: PublicKeyResolver;
  tierResolver?: AssuranceTierResolver;
  webauthnCredentialResolver?: WebAuthnCredentialResolver;
  assuranceFloor?: AssuranceTier;
  nowMs?: number;
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
} & ApprovalVerificationOptions): ShowcaseAppendResult {
  return recordApprovalDecision(options, "approval_recorded", options.decision, "approval_statement");
}

export function rejectShowcaseApproval(options: {
  context: ResolvedWorkspaceContext;
  runId: string;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  statement: string;
  idempotencyKey: string;
  recordedAt?: string;
} & ApprovalVerificationOptions): ShowcaseAppendResult {
  return recordApprovalDecision(options, "approval_rejected", "rejected", "rejection_statement");
}

// The single gate both approve and reject flow through. Trust is COMPUTED from
// the signed token; nothing about trust is taken from the caller's word.
function recordApprovalDecision(
  options: {
    context: ResolvedWorkspaceContext;
    runId: string;
    decision?: "approved" | "approved_with_known_gaps" | "rejected";
    actorType: ShowcaseActorType;
    hostSurface: HostSurface;
    statement: string;
    idempotencyKey: string;
    recordedAt?: string;
  } & ApprovalVerificationOptions,
  eventType: "approval_recorded" | "approval_rejected",
  decision: "approved" | "approved_with_known_gaps" | "rejected",
  statementKey: "approval_statement" | "rejection_statement"
): ShowcaseAppendResult {
  const read = readShowcaseEvents(options.context, options.runId);

  // Idempotency FIRST: a re-submit of the same decision returns the existing
  // event WITHOUT re-verifying or re-burning (the ledger has since changed, so a
  // fresh binding recompute would spuriously mismatch, and the nonce is burned).
  const existing = read.events.find((event) => event.idempotency_key === options.idempotencyKey);
  if (existing) {
    return appendResult(options.context, existing);
  }

  const start = read.events.find((event) => event.event_type === "run_started");
  const plan = start?.payload.plan as PresentationPlan | undefined;
  const userRequired = planRequiresUserApproval(plan);
  const assuranceFloor = approvalAssuranceFloorForPlan(plan);

  // A non-user actor may never stand in for a user-required approval.
  if (options.actorType !== "user") {
    if (userRequired) {
      throw new UseCasesPluginError("Agent cannot record user-required approval.", "showcase.user_required_approval");
    }
  }

  const finish = read.events.slice().reverse().find((event) => event.event_type === "run_finished");
  if (!finish) {
    throw new UseCasesPluginError("User approval requires a finished showcase run.", "showcase.finish_required_for_approval");
  }
  const status = replayShowcaseRun({ context: options.context, runId: options.runId });

  // Decide capture method + optionally verify & burn a signed token.
  let captureMethod = options.actorType === "user" ? "same_channel_operator_confirmation" : "command_handler";
  let embeddedToken: ApprovalToken | undefined;
  let recordedDecision = decision;

  if (options.actorType === "user") {
    if (options.approvalToken) {
      // A signed token was supplied: verify it against the LIVE run + keyring and
      // burn its nonce. This is the ONLY path to a trusted human sign-off.
      const liveBinding = computeApprovalBindingFromEvents(options.runId, read.events);
      const burnedNonces = burnedNonceSet(read.events);
      // Explicit double-spend guard FIRST: once a nonce is burned in the ledger,
      // any resubmission is a replay regardless of how the ledger has since
      // drifted. Surfacing the nonce reason (rather than a downstream binding
      // mismatch) makes the single-use failure unambiguous.
      if (burnedNonces.has(options.approvalToken.jti)) {
        throw new UseCasesPluginError(
          "User approval token rejected: NONCE_BURNED (approval token nonce already burned (replay))",
          "showcase.approval_nonce_burned"
        );
      }
      const verification = verifyApprovalToken({
        token: options.approvalToken,
        resolver: options.resolver ?? (() => undefined),
        tierResolver: options.tierResolver,
        webauthnCredentialResolver: options.webauthnCredentialResolver,
        liveBinding,
        isNonceBurned: (jti) => burnedNonces.has(jti),
        nowMs: options.nowMs,
        assuranceFloor
      });
      if (!verification.ok) {
        throw new UseCasesPluginError(
          `User approval token rejected: ${verification.code} (${verification.message})`,
          approvalFailureCode(verification.code)
        );
      }
      if (eventType === "approval_recorded" && verification.decision === "rejected") {
        throw new UseCasesPluginError(
          "User approval token rejected: DECISION_MISMATCH (rejected token cannot record approval)",
          "showcase.approval_decision_mismatch"
        );
      }
      if (eventType === "approval_rejected" && verification.decision !== "rejected") {
        throw new UseCasesPluginError(
          "User approval token rejected: DECISION_MISMATCH (approval token cannot record rejection)",
          "showcase.approval_decision_mismatch"
        );
      }
      recordedDecision = verification.decision;
      // Burn the nonce ATOMICALLY before the approval, so a concurrent replay of
      // the same token sees it burned and cannot double-spend.
      appendEvent(options.context, options.runId, {
        eventType: "approval_nonce_burned",
        actorType: options.actorType,
        hostSurface: options.hostSurface,
        idempotencyKey: `${options.idempotencyKey}:nonce-burn`,
        recordedAt: options.recordedAt,
        payload: { jti: options.approvalToken.jti, key_id: verification.key_id, run_id: options.runId }
      });
      captureMethod = "host_signed_approval_token";
      embeddedToken = options.approvalToken;
    } else if (userRequired) {
      // User-required plan, no signed token -> stays pending.
      throw new UseCasesPluginError(
        "User approval requires a signed host approval token (out-of-band human sign-off).",
        "showcase.trusted_user_confirmation_required"
      );
    }
  }

  const payload: Record<string, unknown> = {
    decision: recordedDecision,
    approver: { type: options.actorType },
    capture_method: captureMethod,
    [statementKey]: options.statement,
    scope: {
      plan_content_hash: plan?.plan_content_hash ?? "",
      finish_event_id: finish.event_id,
      run_outcome: status.run_outcome,
      known_gap_count: status.known_gaps.length
    }
  };
  if (embeddedToken) {
    payload.approval_token = embeddedToken;
  }

  const event = appendEvent(options.context, options.runId, {
    eventType,
    actorType: options.actorType,
    hostSurface: options.hostSurface,
    idempotencyKey: options.idempotencyKey,
    recordedAt: options.recordedAt,
    payload
  });
  // Reflect the just-verified trust in the returned status: pass the caller's
  // resolver so the embedded token is re-verified and the run reads as approved.
  return appendResult(options.context, event, {
    trustResolver: options.resolver,
    trustTierResolver: options.tierResolver,
    trustWebAuthnCredentialResolver: options.webauthnCredentialResolver
  });
}

// The set of already-burned nonces recorded in the ledger.
function burnedNonceSet(events: ShowcaseEvent[]): Set<string> {
  const burned = new Set<string>();
  for (const event of events) {
    if (event.event_type === "approval_nonce_burned") {
      const jti = (event.payload as { jti?: unknown }).jti;
      if (typeof jti === "string") {
        burned.add(jti);
      }
    }
  }
  return burned;
}

// Map a token failure code to a stable plugin error code.
function approvalFailureCode(code: string): string {
  if (code === "NONCE_BURNED") {
    return "showcase.approval_nonce_burned";
  }
  if (code === "TOKEN_EXPIRED") {
    return "showcase.approval_token_expired";
  }
  if (code === "BINDING_MISMATCH") {
    return "showcase.approval_binding_mismatch";
  }
  if (code === "ASSURANCE_TOO_LOW") {
    return "showcase.approval_assurance_too_low";
  }
  if (code === "ASSURANCE_OVER_CLAIM") {
    return "showcase.approval_assurance_over_claim";
  }
  return "showcase.trusted_user_confirmation_required";
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
    throw new UseCasesPluginError("Correction target must be a verdict event.", "showcase_invalid_correction_target");
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
    throw new UseCasesPluginError("Refusing to append to damaged showcase history.", "showcase_ledger_damaged");
  }
  const existing = read.events.find((event) => event.idempotency_key === options.idempotencyKey);
  const intentDigest = intentDigestFor(options.eventType, options.payload, options.actorType, options.hostSurface);
  if (existing) {
    if (existing.intent_digest === intentDigest) {
      return existing;
    }
    throw new UseCasesPluginError("Idempotency key was reused with different intent.", "showcase_idempotency_conflict");
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

function appendResult(
  context: ResolvedWorkspaceContext,
  event: ShowcaseEvent,
  trustOptions: ReplayTrustOptions = {}
): ShowcaseAppendResult {
  return {
    schema_version: 1,
    run_id: event.run_id,
    appended_event_ids: [event.event_id],
    event,
    status: replayShowcaseEvents(event.run_id, readShowcaseEvents(context, event.run_id).events, true, trustOptions)
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
