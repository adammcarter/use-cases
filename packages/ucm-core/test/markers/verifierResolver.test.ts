import { describe, expect, test } from "vitest";
import {
  DEFAULT_CONVENTION_VERIFIER_ID,
  resolveRowVerifiers
} from "../../src/markers/index.js";

const SLUG = "presentation_skills.evidence.crash_durable_ledger_writes";

describe("resolveRowVerifiers", () => {
  test("returns the explicit verifier when declared in policy.verifiers (with {slug} substituted)", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: {
        mode: "requirements",
        verifiers: {
          ledger_fsync: {
            kind: "script",
            evidence_kind: "test_result",
            command: ["pnpm", "-s", "vitest", "run", "test/markers/durableWrite.test.ts"],
            inputs: ["src/{slug}/x.ts"],
            timeout_seconds: 300
          }
        },
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["ledger_fsync"], minimum_count: 1 }
        ]
      }
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

  test("falls back to the default-convention verifier with {slug} substituted when undeclared", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: {
        mode: "requirements",
        requirements: [
          {
            evidence_kind: "test_result",
            required_verifiers: [DEFAULT_CONVENTION_VERIFIER_ID],
            minimum_count: 1
          }
        ]
      }
    });
    expect(res).toEqual([
      {
        verifier_id: "acceptance",
        status: "resolved",
        source: "default_convention",
        kind: "script",
        evidence_kind: "test_result",
        command: ["pnpm", "-s", "vitest", "run", `tests/use-cases/${SLUG}.test.ts`],
        inputs: [`tests/use-cases/${SLUG}.test.ts`]
      }
    ]);
  });

  test("marks a truly-unresolvable verifier blocked rather than throwing", () => {
    const res = resolveRowVerifiers({
      slug: SLUG,
      verification_policy: {
        mode: "requirements",
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["script"], minimum_count: 1 }
        ]
      }
    });
    expect(res).toHaveLength(1);
    const [only] = res;
    expect(only.verifier_id).toBe("script");
    expect(only.status).toBe("blocked");
    if (only.status === "blocked") {
      expect(only.reason).toMatch(/not declared/);
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
