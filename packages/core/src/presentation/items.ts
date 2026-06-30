import type { EvidenceSnapshot } from "../evidence/types.js";
import type { HostSurface, LoadedUseCase } from "../useCases/types.js";
import { choosePresentationFormat, formatToDeliveryKind } from "./presentationFormat.js";
import {
  expectedObservations,
  policySnapshot,
  resolvedSteps,
  verificationRequirements
} from "./planHelpers.js";
import type { DeliveryKind } from "./types.js";
import type {
  PlanGap,
  PresentationCandidate,
  PresentationPlanItem,
  RequiredEvidenceSummary,
  SelectionProfile
} from "./types.js";

/**
 * Item transforms & plan-content assembly: turning a selected candidate into a
 * fully-resolved plan item (delivery kind, presentation format, required
 * evidence, evidence/freshness summaries, gaps) plus the per-mode section and
 * plan-level gap construction that depend on the resolved items.
 */

export function toPlanItem(
  candidate: PresentationCandidate,
  evidence: EvidenceSnapshot,
  profile: SelectionProfile,
  _hostSurface: HostSurface
): PresentationPlanItem {
  const useCase = candidate.useCase;
  const evidenceSummary = evidenceForUseCase(evidence, useCase);
  const requiredEvidence = requiredEvidenceFor(useCase, evidenceSummary.status);
  const gaps = gapsForItem(useCase, evidenceSummary.readiness, requiredEvidence);
  const baseDeliveryKind = baseDeliveryKindFor(useCase, profile.mode);
  const presentationFormat = choosePresentationFormat({
    baseDeliveryKind,
    needsUser: needsUserActor(useCase),
    // v1: auto-selection emits testing / reviewing / explaining / user_led.
    // `comparing` and `inspecting` are reachable only via hand-authored plans
    // until row affordances (isContrast / artifact hints) land -- see the spec
    // open questions.
    isContrast: false
  });
  const deliveryKind = formatToDeliveryKind(presentationFormat, baseDeliveryKind);
  return {
    plan_item_id: `item.${useCase.value.id}`,
    presentation_format: presentationFormat,
    delivery_kind: deliveryKind,
    scenario_scope: useCase.value.scenarios?.length ? "explicit" : "whole_use_case",
    use_case_id: useCase.value.id,
    scenario_ids: (useCase.value.scenarios ?? []).map((scenario) => scenario.id),
    use_case_content_hash: useCase.semanticHash,
    estimated_seconds: profile.fallbackEstimateSeconds,
    estimate_source: "default_profile",
    setup_steps: [],
    resolved_steps: resolvedSteps(useCase),
    expected_observations: expectedObservations(useCase),
    teardown_steps: [],
    required_permissions: [],
    safety_constraints: [],
    verification_policy_snapshot: policySnapshot(useCase.value.verification_policy),
    approval_policy_snapshot: policySnapshot(useCase.value.approval_policy),
    approval_resolution_required_at_run_start: policySnapshot(useCase.value.approval_policy).mode === "ask",
    required_evidence: requiredEvidence,
    evidence_summary: {
      readiness: evidenceSummary.readiness,
      active_evidence_ids: evidenceSummary.activeEvidenceIds,
      basis: evidenceSummary.basis
    },
    freshness_summary: {
      state: evidenceSummary.freshnessState,
      basis: evidenceSummary.freshnessBasis
    },
    known_gaps: gaps,
    selection_reasons: candidate.reasons,
    selection_reason_codes: candidate.reasonCodes,
    score_components: candidate.scoreComponents
  };
}

/**
 * The base (verification-derived) delivery kind for an item before a
 * presentation format is chosen. Showcase prefers live-where-safe: it keeps
 * `live_demo` whenever the row carries live_demo verification, otherwise it
 * falls back to the same projection walkthrough uses. This replaces the old
 * hard `showcase ? "live_demo"` force so destructive / external / human-judgment
 * rows get an honest base kind.
 */
function baseDeliveryKindFor(useCase: LoadedUseCase, mode: "showcase" | "walkthrough"): DeliveryKind {
  if (mode === "showcase") {
    const requirements = verificationRequirements(useCase);
    if (requirements.some((requirement) => requirement.evidence_kind === "live_demo")) {
      return "live_demo";
    }
  }
  return deliveryKindFor(useCase);
}

/**
 * True when an item needs a human actor: any verification requirement that
 * lists `user` among its required verifiers, or an approval policy in `ask`
 * mode. Such items are presented with the `user_led` (Over to you) format.
 */
function needsUserActor(useCase: LoadedUseCase): boolean {
  const requirements = verificationRequirements(useCase);
  if (requirements.some((requirement) => requirement.required_verifiers.includes("user"))) {
    return true;
  }
  return policySnapshot(useCase.value.approval_policy).mode === "ask";
}

function deliveryKindFor(useCase: LoadedUseCase): DeliveryKind {
  const requirements = verificationRequirements(useCase);
  if (requirements.some((requirement) => requirement.evidence_kind === "live_demo")) {
    return "live_demo";
  }
  if (requirements.length > 0) {
    return "evidence_review";
  }
  return "explanation";
}

function evidenceForUseCase(evidence: EvidenceSnapshot, useCase: LoadedUseCase): {
  readiness: "available_current" | "available_stale" | "missing" | "invalid" | "unknown" | "ambiguous";
  activeEvidenceIds: string[];
  status: RequiredEvidenceSummary["status"];
  basis: string;
  freshnessState: PresentationPlanItem["freshness_summary"]["state"];
  freshnessBasis: string;
} {
  if (!evidence.complete && evidence.integrity.unknownScopeDamage) {
    return {
      readiness: "unknown",
      activeEvidenceIds: [],
      status: "unknown_due_to_integrity",
      basis: "evidence_integrity_incomplete",
      freshnessState: "unknown",
      freshnessBasis: "evidence_integrity_incomplete"
    };
  }
  const matching = evidence.aggregates.filter(
    (aggregate) =>
      aggregate.status === "active" &&
      aggregate.targetLinks.some((target) => target.use_case_id === useCase.value.id)
  );
  if (matching.length === 0) {
    return {
      readiness: "missing",
      activeEvidenceIds: [],
      status: "missing",
      basis: "no_active_evidence",
      freshnessState: "unknown",
      freshnessBasis: "missing_evidence"
    };
  }
  const semanticMatches = matching.some((aggregate) =>
    aggregate.targetLinks.some(
      (target) => target.use_case_id === useCase.value.id && target.use_case_semantic_hash === useCase.semanticHash
    )
  );
  return {
    readiness: semanticMatches ? "available_current" : "available_stale",
    activeEvidenceIds: matching.map((aggregate) => aggregate.evidenceId),
    status: "candidate_observed",
    basis: semanticMatches ? "active_evidence_semantic_hash_match" : "active_evidence_semantic_hash_mismatch",
    freshnessState: semanticMatches ? "current" : "needs_review",
    freshnessBasis: semanticMatches ? "policy_match" : "use_case_semantic_hash_mismatch"
  };
}

function requiredEvidenceFor(useCase: LoadedUseCase, status: RequiredEvidenceSummary["status"]): RequiredEvidenceSummary[] {
  const requirements = verificationRequirements(useCase);
  if (requirements.length === 0) {
    return [
      {
        evidence_kind: "manual_observation",
        required_verifiers: [],
        minimum_count: 1,
        status: "not_applicable"
      }
    ];
  }
  return requirements.map((requirement) => ({
    evidence_kind: requirement.evidence_kind,
    required_verifiers: requirement.required_verifiers,
    minimum_count: requirement.minimum_count,
    status
  }));
}

function gapsForItem(
  useCase: LoadedUseCase,
  readiness: PresentationPlanItem["evidence_summary"]["readiness"],
  requiredEvidence: RequiredEvidenceSummary[]
): PlanGap[] {
  const gaps: PlanGap[] = [];
  if (requiredEvidence.some((requirement) => requirement.status === "missing")) {
    gaps.push({
      code: "evidence_missing",
      message: "Required evidence is missing; live performance is still required.",
      severity: "warning"
    });
  }
  if (readiness === "available_stale") {
    gaps.push({
      code: "evidence_needs_review",
      message: "Existing evidence targets an older use-case semantic hash.",
      severity: "warning"
    });
  }
  if (useCase.value.approval_policy && policySnapshot(useCase.value.approval_policy).mode === "ask") {
    gaps.push({
      code: "approval_resolution_required",
      message: "Approval policy must be resolved during the later live run.",
      severity: "info"
    });
  }
  if (gaps.length === 0) {
    gaps.push({
      code: "prepared_not_performed",
      message: "This is a prepared plan and has not been performed.",
      severity: "info"
    });
  }
  return gaps;
}

export function planGaps(incompleteInput: boolean): PlanGap[] {
  return incompleteInput
    ? [
        {
          code: "input_integrity_partial",
          message: "The plan was generated from partial input and requires acknowledgement before execution.",
          severity: "warning"
        }
      ]
    : [
        {
          code: "prepared_not_performed",
          message: "The plan is prepared only; no live run has been performed.",
          severity: "info"
        }
      ];
}

export function sectionsFor(mode: "showcase" | "walkthrough", selectedItems: PresentationPlanItem[]) {
  if (mode === "showcase") {
    return [
      {
        section_id: "section.primary-path",
        title: "Primary path",
        purpose: "Show the highest-value user-visible behavior.",
        item_ids: selectedItems.map((item) => item.plan_item_id)
      }
    ];
  }
  const primary = selectedItems.filter((item) => item.use_case_id.includes(".golden")).map((item) => item.plan_item_id);
  const coverage = selectedItems.filter((item) => !primary.includes(item.plan_item_id)).map((item) => item.plan_item_id);
  return [
    {
      section_id: "section.primary-path",
      title: "Primary path",
      purpose: "Establish the main product value.",
      item_ids: primary.length > 0 ? primary : selectedItems.slice(0, 1).map((item) => item.plan_item_id)
    },
    {
      section_id: "section.coverage",
      title: "Coverage",
      purpose: "Walk through alternate, edge, negative, and failure behavior.",
      item_ids: coverage.length > 0 ? coverage : selectedItems.map((item) => item.plan_item_id)
    }
  ];
}
