import type { LoadedUseCase, PresentationCandidate, PresentationMode, SelectionProfile } from "./types.js";

export const SHOWCASE_PROFILE: SelectionProfile = {
  id: "showcase-v1",
  mode: "showcase",
  defaultTimeboxSeconds: 600,
  defaultMaxItems: 5,
  fallbackEstimateSeconds: 120
};

export const WALKTHROUGH_PROFILE: SelectionProfile = {
  id: "walkthrough-v1",
  mode: "walkthrough",
  defaultTimeboxSeconds: 1800,
  defaultMaxItems: 12,
  fallbackEstimateSeconds: 180
};

const VALUE_RANK = {
  critical: 400,
  core: 300,
  supporting: 200,
  long_tail: 100
} as const;

const SHOWCASE_JOURNEY_RANK = {
  golden: 50,
  alternate: 40,
  edge: 30,
  negative: 20,
  failure: 10
} as const;

const WALKTHROUGH_JOURNEY_RANK = {
  golden: 50,
  alternate: 45,
  edge: 45,
  negative: 45,
  failure: 45
} as const;

const FREQUENCY_RANK = {
  common: 30,
  occasional: 20,
  rare: 10
} as const;

export function scoreUseCase(item: LoadedUseCase, mode: PresentationMode, changed: boolean): PresentationCandidate["scoreComponents"] {
  const journeyRank = mode === "showcase" ? SHOWCASE_JOURNEY_RANK : WALKTHROUGH_JOURNEY_RANK;
  return {
    changed: changed ? 1_000 : 0,
    value: VALUE_RANK[item.value.value_tier],
    journey: journeyRank[item.value.journey_role],
    frequency: FREQUENCY_RANK[item.value.usage_frequency]
  };
}

export function compareCandidates(left: PresentationCandidate, right: PresentationCandidate): number {
  for (const key of ["changed", "value", "journey", "frequency"] as const) {
    const diff = right.scoreComponents[key] - left.scoreComponents[key];
    if (diff !== 0) {
      return diff;
    }
  }
  const featureDiff = left.useCase.feature.id.localeCompare(right.useCase.feature.id);
  if (featureDiff !== 0) {
    return featureDiff;
  }
  return left.useCase.value.id.localeCompare(right.useCase.value.id);
}

export function scoreReasons(item: LoadedUseCase, changed: boolean, mode: PresentationMode): {
  codes: string[];
  reasons: string[];
} {
  const codes: string[] = [];
  const reasons: string[] = [];
  if (changed) {
    codes.push("changed_source");
    reasons.push("Matched an explicitly changed source path.");
  }
  codes.push(`value_${item.value.value_tier}`);
  reasons.push(`${sentenceCase(item.value.value_tier)} value use case.`);
  codes.push(`journey_${item.value.journey_role}`);
  reasons.push(
    mode === "showcase" && item.value.journey_role === "golden"
      ? "Golden path is preferred for a high-level showcase."
      : `${sentenceCase(item.value.journey_role)} journey coverage.`
  );
  codes.push(`frequency_${item.value.usage_frequency}`);
  reasons.push(`${sentenceCase(item.value.usage_frequency)} usage frequency.`);
  return { codes, reasons };
}

function sentenceCase(value: string): string {
  return value.replaceAll("_", " ").replace(/^\w/, (first) => first.toUpperCase());
}
