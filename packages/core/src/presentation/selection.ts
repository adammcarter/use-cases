import type { PresentationCandidate } from "./types.js";

/**
 * Selection within limits: walk the ordered candidates and take items until the
 * item cap or the timebox (using a flat per-item estimate) is reached.
 */

export function selectWithinLimits(
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
