import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import { resolveWorkspaceContext } from "../../src/roots.js";

// Increment 1 (variant parametrization): a use-case may declare an additive,
// optional `variants[]`. Each variant becomes an addressable row downstream; here
// we only prove the SCHEMA + LOADER accept a family, enforce key rules, and — the
// load-bearing compat property — do NOT change the semantic hash of any row that
// omits `variants`. See DESIGN.md §3, §8.

type VariantSpec = { key: string; title?: string };

function familyYaml(id: string, variants: VariantSpec[] | null): string {
  const lines = [
    "schema_version: 1",
    "feature:",
    "  id: cart",
    "  name: Cart",
    "  summary: Users manage cart quantities.",
    "use_cases:",
    `  - id: ${id}`,
    "    title: Cart quantity handling",
    "    lifecycle: active",
    "    value_tier: critical",
    "    journey_role: golden",
    "    usage_frequency: common",
    "    actor: shopper",
    "    intent: Set a cart quantity.",
    "    preconditions: [Cart exists.]",
    "    trigger: Shopper sets a quantity.",
    "    scenarios:",
    `      - id: ${id}.web`,
    "        kind: steps",
    "        steps: [Set a quantity.]",
    "    observable_outcomes: [The cart reflects the quantity.]",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    verification_policy:",
    "      mode: none",
    "    approval_policy:",
    "      mode: none"
  ];
  if (variants) {
    lines.push("    variants:");
    for (const variant of variants) {
      lines.push(`      - key: ${variant.key}`);
      if (variant.title) {
        lines.push(`        title: ${variant.title}`);
      }
    }
  }
  lines.push("");
  return lines.join("\n");
}

function loadFamily(id: string, variants: VariantSpec[] | null) {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "uc-variants-"));
  const useCasesRoot = join(workspaceRoot, "use-cases");
  mkdirSync(useCasesRoot, { recursive: true });
  writeFileSync(join(useCasesRoot, "cart.yml"), familyYaml(id, variants), "utf8");
  return loadUseCaseMatrix({ context: resolveWorkspaceContext({ workspaceRoot }) });
}

describe("variant parametrization — schema + loader (increment 1)", () => {
  // 0 / 1 / many: the canonical parametrization axis.
  test.each([
    ["one", [{ key: "only" }]],
    ["many", [{ key: "zero" }, { key: "one" }, { key: "many" }, { key: "negative" }]]
  ] as const)("loads a variant family (%s)", (_label, variants) => {
    const snapshot = loadFamily("cart.quantity", variants as VariantSpec[]);

    expect(snapshot.diagnostics).toEqual([]);
    expect(snapshot.addressableUseCases).toHaveLength(1);
    expect(snapshot.addressableUseCases[0]?.value.variants).toEqual(variants);
  });

  test("a use-case with NO variants loads and never gains a variants field", () => {
    const snapshot = loadFamily("cart.quantity", null);
    expect(snapshot.diagnostics).toEqual([]);
    expect(snapshot.addressableUseCases).toHaveLength(1);
    // No default may be materialised — that would change the semantic hash.
    expect(snapshot.addressableUseCases[0]?.value).not.toHaveProperty("variants");
  });

  test("rejects duplicate variant keys within a family", () => {
    const snapshot = loadFamily("cart.quantity", [{ key: "dup" }, { key: "dup" }]);
    expect(snapshot.addressableUseCases).toHaveLength(0);
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({ code: "duplicate_variant_key" })
    );
  });

  test("rejects a variant key with an illegal charset", () => {
    const snapshot = loadFamily("cart.quantity", [{ key: "Bad Key!" }]);
    expect(snapshot.addressableUseCases).toHaveLength(0);
    expect(snapshot.diagnostics.some((d) => d.severity === "error")).toBe(true);
  });

  // Compat guard (DESIGN.md §8): adding the optional `variants` field to the schema
  // must not change the semantic hash of a use-case that omits it. This golden hash
  // is pinned to the 0.4.1 algorithm output; if a default is ever materialised onto a
  // no-variants row, computeSemanticHash sees the extra field and this breaks — which
  // is exactly what we want it to catch.
  test("no-variants semantic hash is stable (golden)", () => {
    const snapshot = loadFamily("cart.quantity", null);
    expect(snapshot.addressableUseCases[0]?.semanticHash).toBe(NO_VARIANTS_GOLDEN_HASH);
  });
});

// Computed from the pre-feature (0.4.1) loader against the exact no-variants fixture
// above. Pinned deliberately — see the test comment.
const NO_VARIANTS_GOLDEN_HASH =
  "sha256:79c8840a1ff57a32dbc919d2e83ee97744e14aa99de6a92f7a2dc977efa5518b";
