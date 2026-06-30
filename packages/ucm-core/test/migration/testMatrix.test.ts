import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

function workspaceWith(source: string): ResolvedWorkspaceContext {
  const root = mkdtempSync(join(tmpdir(), "ucp-migrate-"));
  writeFileSync(join(root, "TEST-MATRIX.md"), source);
  return { workspace_root: root, data_root: root } as unknown as ResolvedWorkspaceContext;
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

describe("migrateTestMatrix behaviour column header", () => {
  it("preserves behaviour text from a British 'Behaviour' header", () => {
    const context = workspaceWith(
      [
        "# TEST-MATRIX",
        "",
        "| ID | Feature | Behaviour | When | Then |",
        "| --- | --- | --- | --- | --- |",
        "| AUTH-1 | Auth | User signs in with a valid password | Submit the login form | The dashboard loads |",
        ""
      ].join("\n")
    );

    const result = migrateTestMatrix({ context, sourcePath: "TEST-MATRIX.md", mode: "dry_run" });

    expect(result.summary.rows_seen).toBe(1);
    const draft = result.drafts.find((item) => item.feature_id === "migrated.auth");
    expect(draft).toBeDefined();
    // The Behaviour cell drives both the scenario title and the use-case intent;
    // an unrecognised header would drop this text and the row would lose its behaviour.
    expect(draft!.content).toContain("User signs in with a valid password");
  });
});
