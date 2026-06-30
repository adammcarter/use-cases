import { computeSemanticHash } from "../schema/index.js";
import { compareCandidates } from "./scoring.js";
import { buildCandidates, exclusionFor, summarizeCandidates } from "./candidates.js";
import { orderWalkthrough } from "./ordering.js";
import { selectWithinLimits } from "./selection.js";
import { planGaps, sectionsFor, toPlanItem } from "./items.js";
import { evidenceDigest, matrixDigest, planId, workflowSnapshot } from "./snapshot.js";
import { normalizePaths } from "./planHelpers.js";
import type {
  PresentationPlan,
  PresentationPlanResult,
  PresentationPlanSelectionOptions,
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
