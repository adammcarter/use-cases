import type { Diagnostic } from "../schema/index.js";
import type { HostSurface, MatrixSnapshot } from "../useCases/types.js";

export type EvidenceEventType =
  | "evidence_recorded"
  | "evidence_corrected"
  | "evidence_voided"
  | "evidence_superseded"
  | "evidence_invalidated";

export type EvidenceResult = "pass" | "fail" | "inconclusive" | "observed";
export type EvidenceKind =
  | "manual_observation"
  | "agent_observation"
  | "command_result"
  | "test_result"
  | "live_demo"
  | "artifact_review"
  | "host_conformance"
  | "url";

export type EvidenceTarget = {
  use_case_id: string;
  scenario_id?: string;
  use_case_semantic_hash: string;
};

export type EvidenceObservation = {
  targets: EvidenceTarget[];
  kind: EvidenceKind;
  captured_at: string;
  result: EvidenceResult;
  summary: string;
  producer: {
    type: "user" | "agent" | "script" | "system";
    identity?: string;
  };
  method: {
    type: "reported" | "observed" | "structured_command";
    executable?: string;
    argv?: string[];
  };
  evidence_kind?: EvidenceKind;
  use_case_ids?: string[];
  verifier?: { type: "user" | "agent" | "script" };
  verdict?: "pass" | "partial" | "fail" | "waived" | "blocked";
};

export type EvidenceEvent = {
  schema_version: number;
  event_type: EvidenceEventType;
  event_id: string;
  aggregate_id: string;
  sequence: number;
  recorded_at: string;
  actor_type: "user" | "agent" | "script" | "system";
  host_surface: HostSurface;
  idempotency_key: string;
  intent_digest?: string;
  payload?: EvidenceObservation;
  replacement?: EvidenceObservation;
  target_event_id?: string;
  replacement_evidence_id?: string;
  reason?: string;
};

export type EvidenceLedgerResult = {
  path: string;
  complete: boolean;
  events_loaded: number;
  torn_tail: boolean;
  unknown_scope_damage: boolean;
};

export type EvidenceAssurance = {
  origin: "user" | "agent" | "script" | "system";
  capture_method: "reported" | "observed" | "executed" | "imported";
  execution_method: "none" | "manual" | "command" | "test";
  integrity: "none" | "caller_reported_digest" | "tool_computed_digest";
  reproducibility: "none" | "instructions" | "structured_command";
  result: EvidenceResult;
  class: "reference" | "reported" | "observed" | "reproducible";
};

export type EvidenceAggregateState = {
  evidenceId: string;
  status: "active" | "voided" | "invalidated" | "superseded" | "invalid";
  effectiveObservation?: EvidenceObservation;
  targetLinks: EvidenceTarget[];
  assurance: EvidenceAssurance | Record<string, never>;
  freshnessInputs: {
    captured_at?: string;
    use_case_semantic_hashes: string[];
    explicit_invalidation?: boolean;
  };
  eventIds: string[];
  replacementEvidenceId?: string;
};

export type EvidenceSnapshot = {
  complete: boolean;
  integrity: {
    state: "clean" | "partial" | "unusable";
    unknownScopeDamage: boolean;
    invalidAggregateCount: number;
    tornTailCount: number;
  };
  ledgers: EvidenceLedgerResult[];
  aggregates: EvidenceAggregateState[];
  diagnostics: Diagnostic[];
  counts: {
    ledgers: number;
    events_loaded: number;
    aggregates_total: number;
    aggregates_active: number;
    aggregates_invalid: number;
  };
  events: EvidenceEvent[];
};

export type EvidenceStatusResultData = {
  schema_version: 1;
  complete: boolean;
  integrity: {
    state: EvidenceSnapshot["integrity"]["state"];
    unknown_scope_damage: boolean;
    invalid_aggregate_count: number;
    torn_tail_count: number;
  };
  ledgers: Array<{
    path: string;
    complete: boolean;
    events_loaded: number;
    torn_tail: boolean;
    unknown_scope_damage: boolean;
  }>;
  aggregates: Array<{
    evidence_id: string;
    status: EvidenceAggregateState["status"];
    event_ids: string[];
    target_links: EvidenceTarget[];
    assurance: EvidenceAggregateState["assurance"];
    freshness_inputs: EvidenceAggregateState["freshnessInputs"];
  }>;
  counts: EvidenceSnapshot["counts"];
};

export type EvidenceAppendResultData = {
  schema_version: 1;
  appended: boolean;
  event: EvidenceEvent;
  ledger_path: string;
  durability: "file_synced" | "file_and_directory_synced" | "best_effort";
};

export type EvidenceMatrixLink = {
  evidenceId: string;
  useCaseId: string;
  scenarioId?: string;
  resolution: "resolved" | "missing" | "ambiguous" | "unknown_due_to_matrix_incomplete";
  semanticHash: "match" | "mismatch" | "unknown";
  sourcePath: string | null;
};

export type EvidenceFreshnessResult = {
  state: "current" | "needs_review" | "stale" | "unknown" | "invalidated";
  basis: string;
};

export type LinkEvidenceOptions = {
  evidence: EvidenceSnapshot;
  matrix: MatrixSnapshot;
};
