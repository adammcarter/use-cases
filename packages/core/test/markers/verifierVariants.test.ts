import { describe, expect, test } from "vitest";
import { resolveRowVerifiers } from "../../src/markers/verifierResolver.js";

// Increment 3 (variant parametrization): the verifier resolver substitutes a
// `{variant}` token alongside `{slug}`, so one declared family command shards per
// variant. For a variant row the caller passes `slug` = family id and `variant` =
// the variant key (wired in verify, increment 4). See DESIGN.md §4.

function policyWithScript(command: string[]) {
  return {
    mode: "requirements",
    requirements: [{ evidence_kind: "test_result", required_verifiers: ["journey"], minimum_count: 1 }],
    verifiers: { journey: { kind: "script", command } }
  };
}

describe("verifier resolver — {variant} substitution (increment 3)", () => {
  test("substitutes {variant} and {slug} in a script command", () => {
    const [resolved] = resolveRowVerifiers({
      slug: "cart.quantity",
      variant: "zero",
      verification_policy: policyWithScript([
        "npx",
        "vitest",
        "run",
        "tests/use-cases/{slug}.test.ts",
        "-t",
        "{variant}"
      ])
    });

    expect(resolved).toMatchObject({
      status: "resolved",
      command: ["npx", "vitest", "run", "tests/use-cases/cart.quantity.test.ts", "-t", "zero"]
    });
  });

  test("substitutes {variant} everywhere it appears, including inputs", () => {
    const [resolved] = resolveRowVerifiers({
      slug: "cart.quantity",
      variant: "negative",
      verification_policy: {
        mode: "requirements",
        requirements: [
          { evidence_kind: "test_result", required_verifiers: ["journey"], minimum_count: 1 }
        ],
        verifiers: {
          journey: {
            kind: "script",
            command: ["run", "--case", "{variant}"],
            inputs: ["cases/{variant}.json"]
          }
        }
      }
    });

    expect(resolved).toMatchObject({
      status: "resolved",
      command: ["run", "--case", "negative"],
      inputs: ["cases/negative.json"]
    });
  });

  test("without a variant, {slug} still substitutes and {variant} is left untouched", () => {
    // An ordinary (non-variant) row: no variant supplied. The {slug} path is
    // unchanged from today; a stray {variant} is NOT invented away here — verify
    // surfaces that as a spec error (increment 4).
    const [resolved] = resolveRowVerifiers({
      slug: "auth.login",
      verification_policy: policyWithScript(["run", "tests/{slug}.test.ts"])
    });

    expect(resolved).toMatchObject({
      status: "resolved",
      command: ["run", "tests/auth.login.test.ts"]
    });
  });
});
