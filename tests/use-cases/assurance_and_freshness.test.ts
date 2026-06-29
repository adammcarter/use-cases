// Acceptance test for use-case row
//   presentation_skills.evidence.assurance_and_freshness
//
// The row promises: proof strength is distinguished by producer / capture method /
// execution method, and fresh evidence is never conflated with stale, mismatched,
// or explicitly invalidated evidence.
//
// It drives the REAL assurance/freshness primitives the bound code implements
// (packages/ucm-core/src/evidence/assurance.ts: deriveEvidenceAssurance /
// evaluateEvidenceFreshness) and asserts the distinct facets and freshness states
// directly — these are pure, deterministic classifiers.
import { describe, expect, test } from "vitest";
import {
  deriveEvidenceAssurance,
  evaluateEvidenceFreshness
} from "../../packages/ucm-core/src/evidence/index.js";

describe("assurance_and_freshness", () => {
  test("assurance class reflects how the proof was captured", () => {
    // A URL reference is the weakest class.
    expect(deriveEvidenceAssurance({ kind: "url", origin: "agent", captureMethod: "reported" }).class).toBe(
      "reference"
    );
    // A reported agent observation is "reported".
    expect(
      deriveEvidenceAssurance({ kind: "agent_observation", origin: "agent", captureMethod: "reported" }).class
    ).toBe("reported");
    // A user-observed manual check is "observed".
    expect(
      deriveEvidenceAssurance({ kind: "manual_observation", origin: "user", captureMethod: "observed" }).class
    ).toBe("observed");
    // An executed test is the strongest: "reproducible" with a structured command.
    const executed = deriveEvidenceAssurance({
      kind: "test_result",
      origin: "script",
      captureMethod: "executed",
      executionMethod: "test",
      exitStatus: 0
    });
    expect(executed.class).toBe("reproducible");
    expect(executed.reproducibility).toBe("structured_command");
    expect(executed.result).toBe("pass");
    // A non-zero exit status flips the result to fail without changing the class.
    expect(
      deriveEvidenceAssurance({
        kind: "test_result",
        origin: "script",
        captureMethod: "executed",
        executionMethod: "test",
        exitStatus: 1
      }).result
    ).toBe("fail");
  });

  test("freshness keeps current, stale, mismatched, and invalidated proof distinct", () => {
    // No evaluation context -> unknown (never silently assumed fresh).
    expect(evaluateEvidenceFreshness({ explicitInvalidation: false })).toEqual({
      state: "unknown",
      basis: "missing_evaluation_context"
    });
    // Matching semantic hash under a policy -> current.
    expect(
      evaluateEvidenceFreshness({
        semanticHashMatches: true,
        policy: { semanticHashMismatch: "stale" }
      })
    ).toEqual({ state: "current", basis: "policy_match" });
    // A hash mismatch surfaces as stale (or needs_review) per policy, NOT current.
    expect(
      evaluateEvidenceFreshness({
        semanticHashMatches: false,
        policy: { semanticHashMismatch: "stale" }
      })
    ).toEqual({ state: "stale", basis: "use_case_semantic_hash_mismatch" });
    expect(
      evaluateEvidenceFreshness({
        semanticHashMatches: false,
        policy: { semanticHashMismatch: "needs_review" }
      }).state
    ).toBe("needs_review");
    // An explicit invalidation always wins.
    expect(
      evaluateEvidenceFreshness({
        explicitInvalidation: true,
        semanticHashMatches: true,
        policy: { semanticHashMismatch: "stale" }
      })
    ).toEqual({ state: "invalidated", basis: "explicit_invalidation" });
  });
});
