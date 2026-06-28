import { describe, expect, test } from "vitest";
import {
  DEFAULT_CONVENTION_VERIFIER_ID,
  resolveRowVerifiers
} from "../../src/markers/index.js";

const SLUG = "presentation_skills.evidence.crash_durable_ledger_writes";

// A policy that requires exactly one verifier id, with optional declared verifiers.
function policyRequiring(id: string, verifiers?: Record<string, unknown>) {
  return {
    mode: "requirements",
    ...(verifiers ? { verifiers } : {}),
    requirements: [
      { evidence_kind: "test_result", required_verifiers: [id], minimum_count: 1 }
    ]
  };
}

describe("resolveRowVerifiers", () => {
  test("returns the explicit verifier when declared in policy.verifiers (with {slug} substituted)", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: policyRequiring("ledger_fsync", {
        ledger_fsync: {
          kind: "script",
          evidence_kind: "test_result",
          command: ["pnpm", "-s", "vitest", "run", "test/markers/durableWrite.test.ts"],
          inputs: ["src/{slug}/x.ts"],
          timeout_seconds: 300
        }
      })
    });
    expect(res).toEqual([
      {
        verifier_id: "ledger_fsync",
        status: "resolved",
        source: "policy",
        kind: "script",
        evidence_kind: "test_result",
        command: ["pnpm", "-s", "vitest", "run", "test/markers/durableWrite.test.ts"],
        inputs: [`src/${SLUG}/x.ts`],
        timeout_seconds: 300
      }
    ]);
  });

  test("resolves a preset reference declared in policy.verifiers via expandPreset", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: policyRequiring(DEFAULT_CONVENTION_VERIFIER_ID, {
        acceptance: { preset: "js.vitest" }
      })
    });
    // js.vitest IS the former hardcoded default convention — now config-driven.
    expect(res).toEqual([
      {
        verifier_id: "acceptance",
        status: "resolved",
        source: "policy",
        kind: "script",
        evidence_kind: "test_result",
        command: ["pnpm", "-s", "vitest", "run", `tests/use-cases/${SLUG}.test.ts`],
        inputs: [`tests/use-cases/${SLUG}.test.ts`]
      }
    ]);
  });

  test("resolves from the WORKSPACE config's verifiers map when the row does not declare it", () => {
    const res = resolveRowVerifiers(
      { slug: SLUG, verification_policy: policyRequiring("ledger_fsync") },
      {
        verifiers: {
          ledger_fsync: {
            kind: "script",
            evidence_kind: "test_result",
            command: ["make", "verify", "SLUG={slug}"],
            inputs: ["tests/{slug}.spec"]
          }
        }
      }
    );
    expect(res).toEqual([
      {
        verifier_id: "ledger_fsync",
        status: "resolved",
        source: "workspace_config",
        kind: "script",
        evidence_kind: "test_result",
        command: ["make", "verify", `SLUG=${SLUG}`],
        inputs: [`tests/${SLUG}.spec`]
      }
    ]);
  });

  test("the default-convention id resolves via the workspace's verifiers.default", () => {
    const res = resolveRowVerifiers(
      { slug: SLUG, verification_policy: policyRequiring(DEFAULT_CONVENTION_VERIFIER_ID) },
      {
        default: "py",
        verifiers: {
          py: { preset: "python.pytest", timeout_seconds: 120 }
        }
      }
    );
    expect(res).toEqual([
      {
        verifier_id: "acceptance",
        status: "resolved",
        source: "workspace_default",
        kind: "script",
        evidence_kind: "test_result",
        command: ["pytest", `tests/use_cases/${SLUG}_test.py`],
        inputs: [`tests/use_cases/${SLUG}_test.py`],
        timeout_seconds: 120
      }
    ]);
  });

  test("the row's own verifier wins over the workspace config of the same id", () => {
    const res = resolveRowVerifiers(
      {
        slug: SLUG,
        verification_policy: policyRequiring("dup", {
          dup: { kind: "script", evidence_kind: "test_result", command: ["row-wins"] }
        })
      },
      { verifiers: { dup: { kind: "script", evidence_kind: "test_result", command: ["ws-loses"] } } }
    );
    expect(res[0]).toMatchObject({ source: "policy", command: ["row-wins"] });
  });

  test("the default-convention id with NO row verifier and NO workspace default is BLOCKED (never pnpm/vitest)", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: policyRequiring(DEFAULT_CONVENTION_VERIFIER_ID)
    });
    expect(res).toHaveLength(1);
    const [only] = res;
    expect(only.verifier_id).toBe("acceptance");
    expect(only.status).toBe("blocked");
    if (only.status === "blocked") {
      expect(only.reason).toMatch(/no verifier 'acceptance' configured/);
      expect(only.reason).toMatch(/verifiers\.default/);
    }
  });

  test("marks a truly-unresolvable verifier blocked rather than throwing", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: policyRequiring("script")
    });
    expect(res).toHaveLength(1);
    const [only] = res;
    expect(only.verifier_id).toBe("script");
    expect(only.status).toBe("blocked");
    if (only.status === "blocked") {
      expect(only.reason).toMatch(/no verifier 'script' configured/);
    }
  });

  test("a verifiers.default that names no declared verifier is BLOCKED", () => {
    const res = resolveRowVerifiers(
      { slug: SLUG, verification_policy: policyRequiring(DEFAULT_CONVENTION_VERIFIER_ID) },
      { default: "ghost", verifiers: {} }
    );
    expect(res[0].status).toBe("blocked");
    if (res[0].status === "blocked") {
      expect(res[0].reason).toMatch(/verifiers\.default 'ghost'/);
    }
  });

  test("an unknown preset id surfaces as blocked (composes with expandPreset)", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: policyRequiring("custom", { custom: { preset: "ruby.rspec" } })
    });
    expect(res[0].status).toBe("blocked");
    if (res[0].status === "blocked") {
      expect(res[0].reason).toMatch(/unknown verifier preset/);
    }
  });

  test("returns a deterministic sorted + deduped structure", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: {
        mode: "requirements",
        requirements: [
          {
            evidence_kind: "test_result",
            required_verifiers: ["zeta", "acceptance"],
            minimum_count: 1
          },
          {
            evidence_kind: "test_result",
            required_verifiers: ["acceptance", "alpha"],
            minimum_count: 1
          }
        ]
      }
    });
    expect(res.map((entry) => entry.verifier_id)).toEqual(["acceptance", "alpha", "zeta"]);
  });

  test("a mode:none policy demands no verifiers", () => {
    expect(
      resolveRowVerifiers({ slug: SLUG, verification_policy: { mode: "none" } })
    ).toEqual([]);
  });
});
