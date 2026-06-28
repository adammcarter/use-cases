import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { computeSemanticHash } from "../schema/index.js";
import type { EvidenceSnapshot } from "../evidence/types.js";
import type { HostSurface, LoadedUseCase, UseCaseV1 } from "../useCases/types.js";
import { compareCandidates, scoreReasons, scoreUseCase } from "./scoring.js";
import { choosePresentationFormat, formatToDeliveryKind } from "./presentationFormat.js";
import type { DeliveryKind } from "./types.js";
import type {
  CandidateSummary,
  PlanGap,
  PresentationCandidate,
  PresentationPlan,
  PresentationPlanExclusion,
  PresentationPlanItem,
  PresentationPlanResult,
  PresentationPlanSelectionOptions,
  RequiredEvidenceSummary,
  SelectionProfile
} from "./types.js";

const ZERO_HASH = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
const FRESHNESS_POLICY = {
  id: "default-v1",
  digest: computeSemanticHash({ semanticHashMismatch: "needs_review" }),
  semanticHashMismatch: "needs_review" as const
};

export function selectPlan(
  options: PresentationPlanSelectionOptions,
  profile: SelectionProfile
): PresentationPlanResult {
  const generatedAt = options.request.generatedAt ?? new Date().toISOString();
  const freshnessEvaluatedAt = options.request.freshnessEvaluatedAt ?? generatedAt;
  const hostSurface = options.request.hostSurface ?? "unknown";
  const timeboxSeconds = options.request.timeboxSeconds || profile.defaultTimeboxSeconds;
  const maxItems = options.request.maxItems ?? profile.defaultMaxItems;
  const inputIntegrity = {
    matrix: options.matrix.integrity.state,
    evidence: options.evidence.integrity.state
  };
  const incompleteInput = !options.matrix.complete || !options.evidence.complete;
  const candidates = buildCandidates(options, profile, hostSurface);
  const eligible = candidates.filter((candidate) => candidate.eligible);

  if (options.request.strict && incompleteInput) {
    return {
      schema_version: 1,
      outcome: "integrity_blocked",
      plan: null,
      candidate_summary: summarizeCandidates(candidates, []),
      input_integrity: inputIntegrity
    };
  }

  if (eligible.length === 0) {
    return {
      schema_version: 1,
      outcome: "no_eligible_items",
      plan: null,
      candidate_summary: summarizeCandidates(candidates, []),
      input_integrity: inputIntegrity
    };
  }

  const ordered = profile.mode === "walkthrough" ? orderWalkthrough(eligible) : eligible.slice().sort(compareCandidates);
  const selected = selectWithinLimits(ordered, profile.fallbackEstimateSeconds, maxItems, timeboxSeconds);
  const selectedSet = new Set(selected.map((candidate) => candidate.useCase.value.id));
  const selectedItems = selected.map((candidate) =>
    toPlanItem(candidate, options.evidence, profile, hostSurface)
  );
  const exclusions = candidates
    .filter((candidate) => !selectedSet.has(candidate.useCase.value.id))
    .map((candidate) => candidate.exclusion ?? exclusionFor(candidate, "max_items"));
  const knownGaps = planGaps(incompleteInput);
  const readiness = incompleteInput
    ? "partial_due_to_integrity"
    : selectedItems.some((item) => item.known_gaps.some((gap) => gap.severity !== "info"))
      ? "ready_with_evidence_gaps"
      : "ready";
  const planWithoutHash: PresentationPlan = {
    schema_version: 1,
    plan_id: planId(profile.mode, generatedAt),
    plan_content_hash: ZERO_HASH,
    generated_at: generatedAt,
    mode: profile.mode,
    complete: !incompleteInput,
    prepared_not_performed: true,
    readiness,
    integrity_acknowledgement_required: incompleteInput,
    selection_method: "deterministic",
    selection_profile: {
      id: profile.id,
      version: 1,
      digest: computeSemanticHash(profile)
    },
    input_snapshot: {
      matrix_digest: matrixDigest(options),
      evidence_basis_digest: evidenceDigest(options.evidence, selectedItems.map((item) => item.use_case_id)),
      changed_paths: normalizePaths(options.request.changedPaths ?? []),
      freshness_policy: {
        id: FRESHNESS_POLICY.id,
        digest: FRESHNESS_POLICY.digest,
        evaluated_at: freshnessEvaluatedAt
      },
      host_surface: hostSurface,
      workflow: workflowSnapshot(options)
    },
    workspace_snapshot: {
      repository_id: "unknown",
      vcs: "unknown",
      head_revision: "unknown",
      dirty: false,
      working_tree_digest: ZERO_HASH,
      component_id: options.context.component_id,
      captured_at: freshnessEvaluatedAt
    },
    environment_expectations: {
      host_surfaces: [hostSurface]
    },
    audience: options.request.audience,
    timebox_seconds: timeboxSeconds,
    sections: sectionsFor(profile.mode, selectedItems),
    selected_items: selectedItems,
    exclusions,
    known_gaps: knownGaps
  };
  const plan = {
    ...planWithoutHash,
    plan_content_hash: computePresentationPlanHash(planWithoutHash)
  };
  return {
    schema_version: 1,
    outcome: "generated",
    plan,
    candidate_summary: summarizeCandidates(candidates, selected),
    input_integrity: inputIntegrity
  };
}

export function computePresentationPlanHash(plan: PresentationPlan): string {
  const {
    plan_id: _planId,
    generated_at: _generatedAt,
    plan_content_hash: _planContentHash,
    ...stable
  } = plan;
  return computeSemanticHash(stable);
}

function buildCandidates(
  options: PresentationPlanSelectionOptions,
  profile: SelectionProfile,
  hostSurface: HostSurface
): PresentationCandidate[] {
  const requestedUseCaseIds = new Set(options.request.requestedUseCaseIds ?? []);
  return options.matrix.addressableUseCases.map((useCase) => {
    const changed = matchesChangedPath(useCase, options.request.changedPaths ?? []);
    const hardExclusion = hardEligibilityExclusion(useCase, hostSurface);
    const requestExclusion =
      requestedUseCaseIds.size > 0 && !requestedUseCaseIds.has(useCase.value.id)
        ? exclusionForUseCase(useCase, "not_requested", "Use case was not requested for this plan.", false)
        : undefined;
    const scoreComponents = scoreUseCase(useCase, profile.mode, changed);
    const reasons = scoreReasons(useCase, changed, profile.mode);
    return {
      useCase,
      eligible: !hardExclusion && !requestExclusion,
      exclusion: hardExclusion ?? requestExclusion,
      changed,
      scoreComponents,
      reasonCodes: reasons.codes,
      reasons: reasons.reasons
    };
  });
}

function hardEligibilityExclusion(useCase: LoadedUseCase, hostSurface: HostSurface): PresentationPlanExclusion | undefined {
  if (useCase.value.lifecycle !== "active") {
    return exclusionForUseCase(useCase, "lifecycle", "Only active use cases are eligible by default.", true);
  }
  if (!hostMatches(useCase.value, hostSurface)) {
    return exclusionForUseCase(useCase, "host_surface", `Use case is not supported on ${hostSurface}.`, true);
  }
  if (resolvedSteps(useCase).length === 0 || expectedObservations(useCase).length === 0) {
    return exclusionForUseCase(useCase, "not_runnable", "Use case lacks runnable steps or expected observations.", true);
  }
  return undefined;
}

function hostMatches(useCase: UseCaseV1, hostSurface: HostSurface): boolean {
  if (hostSurface === "unknown" || !useCase.host_applicability?.length) {
    return true;
  }
  return useCase.host_applicability.some((item) => item.host_surface === hostSurface && item.supported);
}

function orderWalkthrough(candidates: PresentationCandidate[]): PresentationCandidate[] {
  const ordered: PresentationCandidate[] = [];
  const used = new Set<string>();
  const sorted = candidates.slice().sort(compareCandidates);
  takeFirst(sorted, used, ordered, (candidate) =>
    candidate.useCase.value.journey_role === "golden" &&
    (candidate.useCase.value.value_tier === "critical" || candidate.useCase.value.value_tier === "core")
  );
  for (const role of ["alternate", "edge", "negative", "failure"] as const) {
    takeFirst(sorted, used, ordered, (candidate) => candidate.useCase.value.journey_role === role);
  }
  for (const candidate of sorted) {
    if (!used.has(candidate.useCase.value.id)) {
      used.add(candidate.useCase.value.id);
      ordered.push(candidate);
    }
  }
  return ordered;
}

function takeFirst(
  candidates: PresentationCandidate[],
  used: Set<string>,
  ordered: PresentationCandidate[],
  predicate: (candidate: PresentationCandidate) => boolean
): void {
  const match = candidates.find((candidate) => !used.has(candidate.useCase.value.id) && predicate(candidate));
  if (match) {
    used.add(match.useCase.value.id);
    ordered.push(match);
  }
}

function selectWithinLimits(
  ordered: PresentationCandidate[],
  estimatedSeconds: number,
  maxItems: number,
  timeboxSeconds: number
): PresentationCandidate[] {
  const selected: PresentationCandidate[] = [];
  let usedSeconds = 0;
  for (const candidate of ordered) {
    if (selected.length >= maxItems) {
      break;
    }
    if (usedSeconds + estimatedSeconds > timeboxSeconds) {
      break;
    }
    selected.push(candidate);
    usedSeconds += estimatedSeconds;
  }
  return selected;
}

function toPlanItem(
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

function verificationRequirements(useCase: LoadedUseCase): Array<{
  evidence_kind: string;
  required_verifiers: string[];
  minimum_count: number;
}> {
  const policy = policySnapshot(useCase.value.verification_policy);
  if (policy.mode !== "requirements" || !Array.isArray(policy.requirements)) {
    return [];
  }
  return policy.requirements
    .filter(isRequirement)
    .map((requirement) => ({
      evidence_kind: requirement.evidence_kind,
      required_verifiers: requirement.required_verifiers,
      minimum_count: requirement.minimum_count
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

function planGaps(incompleteInput: boolean): PlanGap[] {
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

function sectionsFor(mode: "showcase" | "walkthrough", selectedItems: PresentationPlanItem[]) {
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

function summarizeCandidates(candidates: PresentationCandidate[], selected: PresentationCandidate[]): CandidateSummary {
  const selectedIds = new Set(selected.map((candidate) => candidate.useCase.value.id));
  const exclusions = candidates.filter((candidate) => !selectedIds.has(candidate.useCase.value.id));
  return {
    considered: candidates.length,
    eligible: candidates.filter((candidate) => candidate.eligible).length,
    selected: selected.length,
    excluded: exclusions.length,
    excluded_by_reason: countByReason(exclusions.map((candidate) => candidate.exclusion?.reason_code ?? "max_items"))
  };
}

function countByReason(reasons: string[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const reason of reasons) {
    counts[reason] = (counts[reason] ?? 0) + 1;
  }
  return counts;
}

function exclusionFor(candidate: PresentationCandidate, reasonCode: string): PresentationPlanExclusion {
  return exclusionForUseCase(
    candidate.useCase,
    reasonCode,
    reasonCode === "timebox"
      ? "Higher-priority items consumed the available timebox."
      : "Higher-priority items consumed the available item cap.",
    false
  );
}

function exclusionForUseCase(
  useCase: LoadedUseCase,
  reasonCode: string,
  reason: string,
  blocking: boolean
): PresentationPlanExclusion {
  return {
    use_case_id: useCase.value.id,
    reason_code: reasonCode,
    reason,
    blocking
  };
}

function resolvedSteps(useCase: LoadedUseCase): string[] {
  const scenarioSteps = (useCase.value.scenarios ?? []).flatMap((scenario) => {
    if ("steps" in scenario && Array.isArray(scenario.steps)) {
      return scenario.steps;
    }
    const given = "given" in scenario && Array.isArray(scenario.given) ? scenario.given : [];
    const when = "when" in scenario && Array.isArray(scenario.when) ? scenario.when : [];
    const then = "then" in scenario && Array.isArray(scenario.then) ? scenario.then : [];
    return [...given, ...when, ...then];
  });
  return scenarioSteps.filter((step): step is string => typeof step === "string" && step.length > 0);
}

function expectedObservations(useCase: LoadedUseCase): string[] {
  const scenarioOutcomes = (useCase.value.scenarios ?? []).flatMap((scenario) =>
    "observable_outcomes" in scenario && Array.isArray(scenario.observable_outcomes)
      ? scenario.observable_outcomes
      : []
  );
  const useCaseOutcomes = Array.isArray(useCase.value.observable_outcomes) ? useCase.value.observable_outcomes : [];
  return uniqueStrings([...scenarioOutcomes, ...useCaseOutcomes].filter(
    (outcome): outcome is string => typeof outcome === "string" && outcome.length > 0
  ));
}

function matchesChangedPath(useCase: LoadedUseCase, changedPaths: readonly string[]): boolean {
  if (changedPaths.length === 0) {
    return false;
  }
  const changed = new Set(normalizePaths(changedPaths));
  return (useCase.value.source_refs ?? []).some(
    (sourceRef) => sourceRef.kind === "file" && changed.has(normalizePath(sourceRef.path))
  );
}

function normalizePaths(paths: readonly string[]): string[] {
  return paths.map(normalizePath).sort();
}

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

function matrixDigest(options: PresentationPlanSelectionOptions): string {
  return computeSemanticHash({
    complete: options.matrix.complete,
    integrity: options.matrix.integrity,
    use_cases: options.matrix.addressableUseCases.map((item) => ({
      id: item.value.id,
      semantic_hash: item.semanticHash,
      source_path: item.source.path
    }))
  });
}

function evidenceDigest(evidence: EvidenceSnapshot, useCaseIds: string[]): string {
  const ids = new Set(useCaseIds);
  const aggregates = evidence.aggregates
    .filter((aggregate) => aggregate.targetLinks.some((target) => ids.has(target.use_case_id)))
    .map((aggregate) => ({
      evidence_id: aggregate.evidenceId,
      status: aggregate.status,
      event_ids: aggregate.eventIds,
      target_links: aggregate.targetLinks,
      freshness_inputs: aggregate.freshnessInputs
    }));
  return computeSemanticHash({
    complete: evidence.complete,
    integrity: evidence.integrity,
    aggregates
  });
}

function workflowSnapshot(options: PresentationPlanSelectionOptions): PresentationPlan["input_snapshot"]["workflow"] {
  const configPath = join(options.context.workspace_root, "presentation-skills.yml");
  if (!existsSync(configPath)) {
    return { effective_mode: "continuous", source: "default", advisory: true };
  }
  const source = readFileSync(configPath, "utf8");
  const effectiveMode = source.match(/^default_workflow_mode:\s*([a-z_]+)/m)?.[1] ?? "continuous";
  return {
    effective_mode: effectiveMode,
    source: source.match(/^default_workflow_mode:/m) ? "workspace_config" : "default",
    advisory: true
  };
}

function planId(mode: "showcase" | "walkthrough", generatedAt: string): string {
  return `plan.${mode}.${generatedAt.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")}`;
}

function policySnapshot(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : { mode: "none" };
}

function isRequirement(value: unknown): value is {
  evidence_kind: string;
  required_verifiers: string[];
  minimum_count: number;
} {
  return (
    isRecord(value) &&
    typeof value.evidence_kind === "string" &&
    Array.isArray(value.required_verifiers) &&
    value.required_verifiers.every((item) => typeof item === "string") &&
    typeof value.minimum_count === "number"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
