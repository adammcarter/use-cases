import type { ResolvedWorkspaceContext } from "../roots.js";
import type { HostSurface } from "../useCases/types.js";
import type { PresentationPlan } from "../presentation/types.js";
import type { AssuranceTier } from "./approvalTiers.js";

export type ShowcaseActorType = "user" | "agent" | "script" | "system";
export type ShowcaseControlMode = "agent_led" | "user_led" | "script_led" | "mixed";
export type ShowcaseVerdict = "pass" | "partial" | "fail" | "waived" | "blocked";
export type ShowcaseEventType =
  | "run_started"
  | "action_recorded"
  | "observation_recorded"
  | "verdict_recorded"
  | "failure_decision_recorded"
  | "run_paused"
  | "run_resumed"
  | "epoch_started"
  | "carry_forward_recorded"
  | "run_finished"
  | "approval_recorded"
  | "approval_rejected"
  | "approval_retracted"
  | "approval_nonce_burned"
  | "observation_corrected"
  | "verdict_corrected"
  | "failure_decision_corrected"
  | "carry_forward_corrected"
  | "finish_corrected";

export type ShowcaseEvent = {
  schema_version: 1;
  event_type: ShowcaseEventType;
  event_id: string;
  run_id: string;
  aggregate_id: string;
  sequence: number;
  recorded_at: string;
  actor_type: ShowcaseActorType;
  host_surface: HostSurface;
  idempotency_key: string;
  intent_digest: string;
  payload: Record<string, unknown>;
};

export type ShowcaseItemStatus = {
  plan_item_id: string;
  verdict: ShowcaseVerdict | "none";
  item_currency: "current" | "stale_due_to_epoch_change" | "carried_forward" | "corrected" | "unknown";
  verification_state: "not_required" | "requirements_unmet" | "requirements_met" | "stale" | "unknown_due_to_integrity";
  latest_observation_event_id: string | null;
  latest_verdict_event_id: string | null;
};

export type ShowcaseRunStatus = {
  schema_version: 1;
  run_id: string;
  complete: boolean;
  execution_status: "prepared_not_performed" | "running" | "paused" | "completed" | "aborted" | "incomplete";
  run_outcome: "prepared_not_performed" | "passed" | "passed_with_waivers" | "partial" | "failed" | "blocked" | "aborted" | "incomplete";
  approval_state:
    | "not_required"
    | "resolution_required"
    | "pending"
    | "approved"
    | "rejected"
    | "approved_with_known_gaps"
    | "stale_due_to_run_change";
  unresolved_failure_count: number;
  approval?: {
    actor_type: ShowcaseActorType;
    assurance_tier: AssuranceTier;
  };
  items: ShowcaseItemStatus[];
  known_gaps: Record<string, unknown>[];
  diagnostic_summary: Record<string, unknown>;
};

export type ShowcaseAppendResult = {
  schema_version: 1;
  run_id: string;
  appended_event_ids: string[];
  event: ShowcaseEvent;
  status: ShowcaseRunStatus;
};

export type ShowcaseRunOptions = {
  context: ResolvedWorkspaceContext;
  runId: string;
};

export type ShowcaseStartOptions = {
  context: ResolvedWorkspaceContext;
  plan: PresentationPlan;
  controlMode: ShowcaseControlMode;
  actorType: ShowcaseActorType;
  hostSurface: HostSurface;
  idempotencyKey: string;
  recordedAt?: string;
  knownGapAcknowledgement?: { acknowledged: true; gaps: string[] };
};
