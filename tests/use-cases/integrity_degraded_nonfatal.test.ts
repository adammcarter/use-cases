// Acceptance test for use-case row
//   presentation_skills.matrix.integrity_degraded_nonfatal
//
// The row promises: when one use-case YAML file is damaged, the matrix loader
// degrades non-fatally — it keeps every VALID sibling addressable, marks overall
// integrity as partial (not clean, not silently dropped), and surfaces the damage
// as a diagnostic. Corruption is visible, never hidden, and never takes down the
// rest of the matrix.
//
// It drives the REAL loader/snapshot builder the bound code implements
// (packages/core/src/useCases/integrity.ts: buildMatrixSnapshot, via
// loadUseCaseMatrix) against the committed `damaged-yaml` fixture, which pairs a
// malformed use-case file with a valid sibling.
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../packages/core/src/roots.js";
import { loadUseCaseMatrix } from "../../packages/core/src/useCases/loadUseCaseMatrix.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

describe("integrity_degraded_nonfatal", () => {
  test("a damaged use-case file keeps valid siblings addressable and surfaces the damage", () => {
    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({
        workspaceRoot: join(fixturesRoot, "damaged-yaml")
      })
    });

    // Degraded, but non-fatally: overall completeness is false and integrity is
    // explicitly "partial" rather than "clean".
    expect(snapshot.complete).toBe(false);
    expect(snapshot.integrity.state).toBe("partial");
    expect(snapshot.integrity.populated).toBe(true);

    // The valid sibling stays fully addressable despite the broken neighbour.
    const addressableIds = snapshot.addressableUseCases.map((item) => item.value.id);
    expect(addressableIds).toContain("auth.login.damage_sibling");

    // The damage is surfaced as a blocking diagnostic, not silently swallowed.
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "parse_error",
        severity: "error",
        source_path: "use-cases/malformed-use-case.yml"
      })
    );
  });
});
