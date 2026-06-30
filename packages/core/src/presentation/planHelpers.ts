import type { LoadedUseCase } from "../useCases/types.js";

/**
 * Low-level, dependency-free helpers shared across the presentation planning
 * modules: path normalisation, use-case fact extraction (steps / observations /
 * verification requirements) and small type guards. These have no dependency on
 * the other presentation modules, so they can be imported anywhere without risk
 * of an import cycle.
 */

export function resolvedSteps(useCase: LoadedUseCase): string[] {
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

export function expectedObservations(useCase: LoadedUseCase): string[] {
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

export function verificationRequirements(useCase: LoadedUseCase): Array<{
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

export function normalizePaths(paths: readonly string[]): string[] {
  return paths.map(normalizePath).sort();
}

export function normalizePath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}

export function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

export function policySnapshot(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : { mode: "none" };
}

export function isRequirement(value: unknown): value is {
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

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
