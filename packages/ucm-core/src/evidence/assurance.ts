import type { EvidenceAssurance, EvidenceFreshnessResult, EvidenceKind } from "./types.js";

export type EvidenceAssuranceInput = {
  kind: EvidenceKind;
  origin: EvidenceAssurance["origin"];
  captureMethod: "reported" | "observed" | "executed" | "imported";
  executionMethod?: EvidenceAssurance["execution_method"];
  exitStatus?: number;
  digestComputedByTool?: boolean;
};

//: @use-case: presentation_skills.evidence.assurance_and_freshness
export function deriveEvidenceAssurance(input: EvidenceAssuranceInput): EvidenceAssurance {
  const executionMethod =
    input.executionMethod ??
    (input.kind === "test_result" ? "test" : input.kind === "command_result" ? "command" : "none");
  const assuranceClass =
    input.kind === "url"
      ? "reference"
      : input.captureMethod === "executed" && (executionMethod === "command" || executionMethod === "test")
        ? "reproducible"
        : input.captureMethod === "observed"
          ? "observed"
          : "reported";

  return {
    origin: input.origin,
    capture_method: input.captureMethod,
    execution_method: executionMethod,
    integrity: input.digestComputedByTool ? "tool_computed_digest" : "none",
    reproducibility: assuranceClass === "reproducible" ? "structured_command" : "none",
    result: input.exitStatus === undefined || input.exitStatus === 0 ? "pass" : "fail",
    class: assuranceClass
  };
}
//: @use-case: end presentation_skills.evidence.assurance_and_freshness

export function evaluateEvidenceFreshness(input: {
  explicitInvalidation?: boolean;
  semanticHashMatches?: boolean;
  policy?: { semanticHashMismatch: "needs_review" | "stale" };
}): EvidenceFreshnessResult {
  if (input.explicitInvalidation) {
    return { state: "invalidated", basis: "explicit_invalidation" };
  }
  if (!input.policy) {
    return { state: "unknown", basis: "missing_evaluation_context" };
  }
  if (input.semanticHashMatches === false) {
    return {
      state: input.policy.semanticHashMismatch,
      basis: "use_case_semantic_hash_mismatch"
    };
  }
  return { state: "current", basis: "policy_match" };
}
