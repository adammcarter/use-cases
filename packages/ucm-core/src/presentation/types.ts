import type { ResolvedWorkspaceContext } from "../roots.js";
import type { EvidenceSnapshot } from "../evidence/types.js";
import type { HostSurface, LoadedUseCase, MatrixSnapshot, UseCaseV1 } from "../useCases/types.js";

export type PresentationMode = "showcase" | "walkthrough";
export type PlanReadiness = "ready" | "ready_with_evidence_gaps" | "partial_due_to_integrity" | "blocked";
export type PresentationPlanOutcome = "generated" | "no_eligible_items" | "integrity_blocked";
export type DeliveryKind = "live_demo" | "evidence_review" | "explanation";

export type PresentationPlanRequest = {
  audience: string;
  timeboxSeconds: number;
  maxItems?: number;
  hostSurface?: HostSurface;
  changedPaths?: readonly string[];
  requestedUseCaseIds?: readonly string[];
  generatedAt?: string;
  freshnessEvaluatedAt?: string;
  strict?: boolean;
};

export type PresentationPlanSelectionOptions = {
  context: ResolvedWorkspaceContext;
  matrix: MatrixSnapshot;
  evidence: EvidenceSnapshot;
  request: PresentationPlanRequest;
};

export type PlanGap = {
  code: string;
  message: string;
  severity: "info" | "warning" | "error";
};

export type RequiredEvidenceSummary = {
  evidence_kind: string;
  required_verifiers: string[];
  minimum_count: number;
  status: "candidate_observed" | "missing" | "unknown_due_to_integrity" | "not_applicable";
};

export type EvidenceReadiness = "available_current" | "available_stale" | "missing" | "invalid" | "unknown" | "ambiguous";

export type PresentationPlanItem = {
  plan_item_id: string;
  delivery_kind: DeliveryKind;
  scenario_scope: "whole_use_case" | "explicit";
  use_case_id: string;
  scenario_ids: string[];
  use_case_content_hash: string;
  estimated_seconds: number;
  estimate_source: "use_case" | "default_profile";
  setup_steps: string[];
  resolved_steps: string[];
  expected_observations: string[];
  teardown_steps: string[];
  required_permissions: string[];
  safety_constraints: string[];
  verification_policy_snapshot: Record<string, unknown>;
  approval_policy_snapshot: Record<string, unknown>;
  approval_resolution_required_at_run_start: boolean;
  required_evidence: RequiredEvidenceSummary[];
  evidence_summary: {
    readiness: EvidenceReadiness;
    active_evidence_ids: string[];
    basis: string;
  };
  freshness_summary: {
    state: "current" | "needs_review" | "stale" | "unknown" | "invalidated";
    basis: string;
  };
  known_gaps: PlanGap[];
  selection_reasons: string[];
  selection_reason_codes: string[];
  score_components: Record<string, number>;
};

export type PresentationPlanSection = {
  section_id: string;
  title: string;
  purpose: string;
  item_ids: string[];
};

export type PresentationPlanExclusion = {
  use_case_id: string;
  reason_code: string;
  reason: string;
  blocking: boolean;
};

export type PresentationPlan = {
  schema_version: 1;
  plan_id: string;
  plan_content_hash: string;
  generated_at: string;
  mode: PresentationMode;
  complete: boolean;
  prepared_not_performed: true;
  readiness: PlanReadiness;
  integrity_acknowledgement_required: boolean;
  selection_method: "deterministic";
  selection_profile: {
    id: string;
    version: 1;
    digest: string;
  };
  input_snapshot: {
    matrix_digest: string;
    evidence_basis_digest: string;
    changed_paths: string[];
    freshness_policy: {
      id: string;
      digest: string;
      evaluated_at: string;
    };
    host_surface: HostSurface;
    workflow: {
      effective_mode: string;
      source: "default" | "workspace_config";
      advisory: true;
    };
  };
  workspace_snapshot: {
    repository_id: string;
    vcs: "git" | "none" | "unknown";
    head_revision: string;
    dirty: boolean;
    working_tree_digest: string;
    component_id: string;
    captured_at: string;
  };
  environment_expectations: {
    host_surfaces: HostSurface[];
  };
  audience: string;
  timebox_seconds: number;
  sections: PresentationPlanSection[];
  selected_items: PresentationPlanItem[];
  exclusions: PresentationPlanExclusion[];
  known_gaps: PlanGap[];
};

export type CandidateSummary = {
  considered: number;
  eligible: number;
  selected: number;
  excluded: number;
  excluded_by_reason: Record<string, number>;
};

export type PresentationPlanResult = {
  schema_version: 1;
  outcome: PresentationPlanOutcome;
  plan: PresentationPlan | null;
  candidate_summary: CandidateSummary;
  input_integrity: {
    matrix: "clean" | "partial" | "unusable";
    evidence: "clean" | "partial" | "unusable";
  };
};

export type PresentationCandidate = {
  useCase: LoadedUseCase;
  eligible: boolean;
  exclusion?: PresentationPlanExclusion;
  changed: boolean;
  scoreComponents: Record<string, number>;
  reasonCodes: string[];
  reasons: string[];
};

export type SelectionProfile = {
  id: "showcase-v1" | "walkthrough-v1";
  mode: PresentationMode;
  defaultTimeboxSeconds: number;
  defaultMaxItems: number;
  fallbackEstimateSeconds: number;
};

export type { EvidenceSnapshot, HostSurface, LoadedUseCase, MatrixSnapshot, UseCaseV1 };
