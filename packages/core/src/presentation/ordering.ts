import { compareCandidates } from "./scoring.js";
import type { PresentationCandidate } from "./types.js";

/**
 * Walkthrough ordering: arrange eligible candidates into a narrative order —
 * a golden critical/core item first, then one of each coverage journey role
 * (alternate, edge, negative, failure), then the remainder by comparator order.
 */

export function orderWalkthrough(candidates: PresentationCandidate[]): PresentationCandidate[] {
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
