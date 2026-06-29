import { describe, expect, it } from "vitest";

import { migrateTestMatrix } from "../../src/migration/index.js";
import { PresentationSkillsError } from "../../src/errors.js";
import type { ResolvedWorkspaceContext } from "../../src/roots.js";

const repoRoot = "/tmp/ucp-migrate-fixture-root";

function contextStub(): ResolvedWorkspaceContext {
  // migrateTestMatrix only reads workspace_root/data_root before the unsafe-path
  // guard throws, so a minimal stub is enough to exercise the diagnostic.
  return {
    workspace_root: repoRoot,
    data_root: repoRoot
  } as unknown as ResolvedWorkspaceContext;
}

describe("migrateTestMatrix unsafe source path diagnostic", () => {
  it("tells the caller the source path must be relative to the repository root and echoes that root", () => {
    let caught: unknown;
    try {
      migrateTestMatrix({
        context: contextStub(),
        sourcePath: "/etc/passwd",
        mode: "dry_run"
      });
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeInstanceOf(PresentationSkillsError);
    const err = caught as PresentationSkillsError;
    expect(err.code).toBe("migration_unsafe_source_path");
    // The message must say what the path is relative TO, and echo the resolved
    // repo root so an agent can self-correct.
    expect(err.message).toMatch(/relative to the repository/i);
    expect(err.message).toContain(repoRoot);
  });

  it("rejects a relative source path that escapes the repository root", () => {
    let caught: unknown;
    try {
      migrateTestMatrix({
        context: contextStub(),
        sourcePath: "../outside/TEST-MATRIX.md",
        mode: "dry_run"
      });
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeInstanceOf(PresentationSkillsError);
    const err = caught as PresentationSkillsError;
    expect(err.code).toBe("migration_unsafe_source_path");
    expect(err.message).toMatch(/relative to the repository/i);
    expect(err.message).toContain(repoRoot);
  });
});
