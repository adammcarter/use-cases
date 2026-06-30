// Acceptance test for use-case row
//   presentation_skills.matrix.coverage_by_value_and_journey
//
// The row promises: the matrix can be sliced by value tier and journey role (and
// lifecycle) so coverage can be reasoned about — a query returns exactly the rows
// matching the requested facets, and an empty query returns the full addressable
// set.
//
// It drives the REAL query engine the bound code implements
// (packages/core/src/useCases/query.ts: queryUseCases) over THIS repository's
// own living use-case matrix, asserting the filters are sound (every returned row
// matches, the slice is a proper non-empty subset) without hard-coding volatile
// row counts.
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../packages/core/src/roots.js";
import { loadUseCaseMatrix } from "../../packages/core/src/useCases/loadUseCaseMatrix.js";
import { queryUseCases } from "../../packages/core/src/useCases/query.js";

const repoRoot = resolve(import.meta.dirname, "../..");

describe("coverage_by_value_and_journey", () => {
  test("filtering by value tier and journey role returns sound, non-empty slices", () => {
    const matrix = loadUseCaseMatrix({ context: resolveWorkspaceContext({ workspaceRoot: repoRoot }) });

    const all = queryUseCases(matrix, {});
    expect(all.length).toBeGreaterThan(0);
    expect(all).toHaveLength(matrix.addressableUseCases.length);

    // Value-tier slice: every returned row is critical, and it is a proper subset.
    const critical = queryUseCases(matrix, { valueTiers: ["critical"] });
    expect(critical.length).toBeGreaterThan(0);
    expect(critical.length).toBeLessThan(all.length);
    expect(critical.every((row) => row.value.value_tier === "critical")).toBe(true);

    // Journey-role slice: every returned row is on the golden path.
    const golden = queryUseCases(matrix, { journeyRoles: ["golden"] });
    expect(golden.length).toBeGreaterThan(0);
    expect(golden.every((row) => row.value.journey_role === "golden")).toBe(true);

    // Combined facets narrow further and never exceed either single-facet slice.
    const criticalGolden = queryUseCases(matrix, {
      valueTiers: ["critical"],
      journeyRoles: ["golden"]
    });
    expect(criticalGolden.length).toBeLessThanOrEqual(Math.min(critical.length, golden.length));
    expect(
      criticalGolden.every(
        (row) => row.value.value_tier === "critical" && row.value.journey_role === "golden"
      )
    ).toBe(true);

    // Results are stably sorted by id.
    const ids = criticalGolden.map((row) => row.value.id);
    expect(ids).toEqual([...ids].sort((left, right) => left.localeCompare(right)));
  });
});
