import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import { loadMarkerRows } from "../../src/markers/cli/shared.js";
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

// ── Increment 2: row expansion ──────────────────────────────────────────────
// A family expands into one marker row per variant (id `family::key`); a use-case
// with no variants stays exactly one ordinary row. Row generation is the single
// place (loadMarkerRows) both verify and scan draw their row set from.

function rowsFor(fileBody: string) {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "uc-variant-rows-"));
  const useCasesRoot = join(workspaceRoot, "use-cases");
  mkdirSync(useCasesRoot, { recursive: true });
  writeFileSync(join(useCasesRoot, "cart.yml"), fileBody, "utf8");
  return loadMarkerRows(resolveWorkspaceContext({ workspaceRoot }));
}

describe("variant parametrization — row expansion (increment 2)", () => {
  test("a family expands into one row per variant, ids `family::key`", () => {
    const loaded = rowsFor(
      familyYaml("cart.quantity", [{ key: "zero" }, { key: "one" }, { key: "many" }])
    );
    expect(loaded.rows.map((row) => row.row_id)).toEqual([
      "cart.quantity::many",
      "cart.quantity::one",
      "cart.quantity::zero"
    ]);
    // Each variant row carries its own key and NOT the family's variants array.
    const zero = loaded.rows.find((row) => row.row_id === "cart.quantity::zero");
    expect(zero?.variant_key).toBe("zero");
    expect(zero).not.toHaveProperty("variants");
    // rowIds mirrors the expanded set (variant ids, no bare family id).
    expect(loaded.rowIds.has("cart.quantity")).toBe(false);
    expect(loaded.rowIds.has("cart.quantity::zero")).toBe(true);
  });

  test("a use-case with no variants stays one ordinary row (no `::`)", () => {
    const loaded = rowsFor(familyYaml("cart.quantity", null));
    expect(loaded.rows.map((row) => row.row_id)).toEqual(["cart.quantity"]);
    expect(loaded.rows[0]).not.toHaveProperty("variant_key");
  });

  test("a mixed matrix expands only the family", () => {
    const body = [
      familyYaml("cart.quantity", [{ key: "one" }, { key: "two" }]).replace(/\n$/, ""),
      // second use-case (ordinary) appended under the same use_cases list
      "  - id: cart.remove",
      "    title: Remove an item",
      "    lifecycle: active",
      "    value_tier: core",
      "    journey_role: alternate",
      "    usage_frequency: occasional",
      "    actor: shopper",
      "    intent: Remove an item.",
      "    preconditions: [Cart has an item.]",
      "    trigger: Shopper removes an item.",
      "    scenarios:",
      "      - id: cart.remove.web",
      "        kind: steps",
      "        steps: [Remove an item.]",
      "    observable_outcomes: [The item is gone.]",
      "    host_applicability:",
      "      - host_surface: codex.cli",
      "        supported: true",
      "    verification_policy:",
      "      mode: none",
      "    approval_policy:",
      "      mode: none",
      ""
    ].join("\n");
    const loaded = rowsFor(body);
    expect(loaded.rows.map((row) => row.row_id).sort()).toEqual([
      "cart.quantity::one",
      "cart.quantity::two",
      "cart.remove"
    ]);
  });
});
