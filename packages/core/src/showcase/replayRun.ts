import type { PresentationPlanItem } from "../presentation/types.js";
import type { ShowcaseEvent, ShowcaseItemStatus, ShowcaseRunStatus } from "./types.js";
import type { ShowcaseRunOptions } from "./types.js";
import { readShowcaseEvents } from "./jsonlLedger.js";
import {
  isTrustedUserDecisionEvent,
  trustedUserDecisionMetadata,
  type ApprovalTrustContext
} from "./approvalAuthority.js";
import type { PublicKeyResolver } from "../markers/proofSignature.js";
import type { AssuranceTierResolver, WebAuthnCredentialResolver } from "../markers/keyring.js";
import type { AssuranceTier } from "./approvalTiers.js";
import { approvalAssuranceFloorForPlan } from "./approvalPolicy.js";

// F3: replay recomputes user-approval trust from the embedded signed token via
// this resolver. Omitted => user approvals are untrusted (fail-closed).
export interface ReplayTrustOptions {
  trustResolver?: PublicKeyResolver;
  trustTierResolver?: AssuranceTierResolver;
  trustWebAuthnCredentialResolver?: WebAuthnCredentialResolver;
  assuranceFloor?: AssuranceTier;
}

export function replayShowcaseRun(options: ShowcaseRunOptions & ReplayTrustOptions): ShowcaseRunStatus {
  const read = readShowcaseEvents(options.context, options.runId);
  return replayShowcaseEvents(options.runId, read.events, read.complete, options);
}

export function replayShowcaseEvents(
  runId: string,
  events: ShowcaseEvent[],
  ledgerComplete = true,
  trustOptions: ReplayTrustOptions = {}
): ShowcaseRunStatus {
  const trust: ApprovalTrustContext = {
    resolver: trustOptions.trustResolver,
    tierResolver: trustOptions.trustTierResolver,
    webauthnCredentialResolver: trustOptions.trustWebAuthnCredentialResolver
  };
  const ordered = events.slice().sort((left, right) => left.sequence - right.sequence);
  const start = ordered.find((event) => event.event_type === "run_started");
  const plan = start?.payload.plan as { selected_items?: PresentationPlanItem[]; known_gaps?: Record<string, unknown>[] } | undefined;
  trust.assuranceFloor = approvalAssuranceFloorForPlan(plan);
  const items = (plan?.selected_items ?? []).map((item) => initialItem(item.plan_item_id));
  const byItem = new Map(items.map((item) => [item.plan_item_id, item]));
  const unresolvedFailures = new Set<string>();
  const verdictEventToItem = new Map<string, string>();
  let hasPerformedEvent = false;
  let paused = false;
  let aborted = false;
  let finished = false;
  let approvalState: ShowcaseRunStatus["approval_state"] = userApprovalRequired(plan) ? "pending" : "not_required";
  let outcomeAffectingEventAfterApproval = false;
  let approvedSequence = 0;
  let approval: ShowcaseRunStatus["approval"] | undefined;
  const ignoredApprovalEvents: string[] = [];

  for (const event of ordered) {
    if (event.event_type !== "run_started" && (event.event_type === "action_recorded" || event.event_type === "observation_recorded")) {
      hasPerformedEvent = true;
    }
    if (approvedSequence > 0 && event.sequence > approvedSequence && affectsApproval(event)) {
      outcomeAffectingEventAfterApproval = true;
    }
    if (event.event_type === "observation_recorded") {
      const item = byItem.get(String(event.payload.plan_item_id));
      if (item) {
        item.latest_observation_event_id = event.event_id;
      }
    }
    if (event.event_type === "verdict_recorded") {
      const item = byItem.get(String(event.payload.plan_item_id));
      if (item) {
        item.verdict = event.payload.verdict as ShowcaseItemStatus["verdict"];
        item.latest_verdict_event_id = event.event_id;
        verdictEventToItem.set(event.event_id, item.plan_item_id);
        item.item_currency = "current";
        item.verification_state = item.verdict === "pass" ? "requirements_met" : "requirements_unmet";
        if (isFailureVerdict(item.verdict)) {
          unresolvedFailures.add(event.event_id);
        }
      }
    }
    if (event.event_type === "failure_decision_recorded") {
      const verdictEventId = String(event.payload.verdict_event_id);
      unresolvedFailures.delete(verdictEventId);
      const planItemId = verdictEventToItem.get(verdictEventId);
      const item = planItemId ? byItem.get(planItemId) : undefined;
      if (item && event.payload.decision === "waive_with_reason") {
        item.verdict = "waived";
        item.verification_state = "not_required";
      }
      if (event.payload.decision === "pause_to_fix") {
        paused = true;
      }
      if (event.payload.decision === "abort") {
        aborted = true;
      }
    }
    if (event.event_type === "verdict_corrected") {
      const item = byItem.get(String(event.payload.plan_item_id));
      if (item) {
        const targetEventId = String(event.payload.target_event_id);
        unresolvedFailures.delete(targetEventId);
        item.verdict = event.payload.corrected_verdict as ShowcaseItemStatus["verdict"];
        item.latest_verdict_event_id = event.event_id;
        verdictEventToItem.set(event.event_id, item.plan_item_id);
        item.item_currency = "corrected";
        item.verification_state = item.verdict === "pass" ? "requirements_met" : "requirements_unmet";
        if (isFailureVerdict(item.verdict)) {
          unresolvedFailures.add(event.event_id);
        }
      }
    }
    if (event.event_type === "epoch_started") {
      for (const planItemId of event.payload.stale_item_ids as string[] | undefined ?? []) {
        const item = byItem.get(planItemId);
        if (item) {
          item.item_currency = "stale_due_to_epoch_change";
          item.verification_state = "stale";
        }
      }
    }
    if (event.event_type === "run_paused") {
      paused = true;
    }
    if (event.event_type === "run_resumed") {
      paused = false;
    }
    if (event.event_type === "run_finished") {
      finished = true;
    }
    if (event.event_type === "approval_recorded") {
      const verified = trustedUserDecisionMetadata(event, trust);
      if (verified) {
        approvalState = event.payload.decision === "approved_with_known_gaps" ? "approved_with_known_gaps" : "approved";
        approvedSequence = event.sequence;
        approval = {
          actor_type: verified.actor_type,
          assurance_tier: verified.assurance_tier
        };
      } else {
        ignoredApprovalEvents.push(event.event_id);
      }
    }
    if (event.event_type === "approval_rejected") {
      if (isTrustedUserDecisionEvent(event, trust)) {
        approvalState = "rejected";
        approvedSequence = event.sequence;
        approval = undefined;
      } else {
        ignoredApprovalEvents.push(event.event_id);
      }
    }
  }

  if (outcomeAffectingEventAfterApproval) {
    approvalState = "stale_due_to_run_change";
    approval = undefined;
  }

  const unresolvedFailureCount = unresolvedFailures.size;
  const anyStale = items.some((item) => item.item_currency === "stale_due_to_epoch_change");
  const anyFail = items.some((item) => item.verdict === "fail");
  const anyBlocked = items.some((item) => item.verdict === "blocked");
  const anyWaived = items.some((item) => item.verdict === "waived");
  const allPassed = items.length > 0 && items.every((item) => item.verdict === "pass");
  const executionStatus = !hasPerformedEvent
    ? "prepared_not_performed"
    : aborted
      ? "aborted"
      : finished && !anyStale
        ? "completed"
        : paused
          ? "paused"
          : "running";
  const runOutcome = !hasPerformedEvent
    ? "prepared_not_performed"
    : aborted
      ? "aborted"
      : anyStale
        ? "incomplete"
        : anyBlocked
          ? "blocked"
          : anyFail
            ? "failed"
            : anyWaived
              ? "passed_with_waivers"
              : allPassed
                ? "passed"
                : "incomplete";

  const knownGaps = hasPerformedEvent
    ? (plan?.known_gaps ?? []).filter((gap) => gap.code !== "prepared_not_performed")
    : plan?.known_gaps ?? [];

  return {
    schema_version: 1,
    run_id: runId,
    complete: ledgerComplete,
    execution_status: ledgerComplete ? executionStatus : "incomplete",
    run_outcome: ledgerComplete ? runOutcome : "incomplete",
    approval_state: approvalState,
    unresolved_failure_count: unresolvedFailureCount,
    ...(approval ? { approval } : {}),
    items,
    known_gaps: knownGaps,
    diagnostic_summary: ignoredApprovalEvents.length > 0 ? { ignored_approval_events: ignoredApprovalEvents } : {}
  };
}

function initialItem(planItemId: string): ShowcaseItemStatus {
  return {
    plan_item_id: planItemId,
    verdict: "none",
    item_currency: "unknown",
    verification_state: "requirements_unmet",
    latest_observation_event_id: null,
    latest_verdict_event_id: null
  };
}

function userApprovalRequired(plan: { selected_items?: PresentationPlanItem[] } | undefined): boolean {
  return (plan?.selected_items ?? []).some((item) =>
    item.approval_policy_snapshot.mode === "predefined" &&
    Array.isArray(item.approval_policy_snapshot.requirements) &&
    item.approval_policy_snapshot.requirements.some((requirement) => requirement.approver_type === "user")
  );
}

function affectsApproval(event: ShowcaseEvent): boolean {
  return [
    "observation_recorded",
    "verdict_recorded",
    "failure_decision_recorded",
    "epoch_started",
    "carry_forward_recorded",
    "run_finished",
    "observation_corrected",
    "verdict_corrected",
    "failure_decision_corrected",
    "carry_forward_corrected",
    "finish_corrected"
  ].includes(event.event_type);
}

function isFailureVerdict(verdict: ShowcaseItemStatus["verdict"]): boolean {
  return verdict === "fail" || verdict === "blocked";
}
