import type { HostSurface, LoadedUseCase, UseCaseV1 } from "../useCases/types.js";
import { scoreReasons, scoreUseCase } from "./scoring.js";
import { expectedObservations, normalizePath, normalizePaths, resolvedSteps } from "./planHelpers.js";
import type {
  CandidateSummary,
  PresentationCandidate,
  PresentationPlanExclusion,
  PresentationPlanSelectionOptions,
  SelectionProfile
} from "./types.js";

/**
 * Candidate building & eligibility: turning addressable use cases into scored
 * presentation candidates, deciding which are eligible, and summarising the
 * considered/excluded set. Exclusion construction lives here too, since it is a
 * candidate concern.
 */

export function buildCandidates(
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

export function summarizeCandidates(candidates: PresentationCandidate[], selected: PresentationCandidate[]): CandidateSummary {
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

export function exclusionFor(candidate: PresentationCandidate, reasonCode: string): PresentationPlanExclusion {
  return exclusionForUseCase(
    candidate.useCase,
    reasonCode,
    reasonCode === "timebox"
      ? "Higher-priority items consumed the available timebox."
      : "Higher-priority items consumed the available item cap.",
    false
  );
}

export function exclusionForUseCase(
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

function matchesChangedPath(useCase: LoadedUseCase, changedPaths: readonly string[]): boolean {
  if (changedPaths.length === 0) {
    return false;
  }
  const changed = new Set(normalizePaths(changedPaths));
  return (useCase.value.source_refs ?? []).some(
    (sourceRef) => sourceRef.kind === "file" && changed.has(normalizePath(sourceRef.path))
  );
}
