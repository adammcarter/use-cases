import { existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { UseCasesPluginError } from "../../src/errors.js";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";
import { resolveContainedPath } from "../../src/roots.js";

const tempDirs: string[] = [];

function tempDir(label: string): string {
  const dir = mkdtempSync(join(tmpdir(), `ucm-init-${label}-`));
  tempDirs.push(dir);
  return dir;
}

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("uc init scaffold path containment", () => {
  test("scaffolds an absolute --repo target from a different cwd through a symlinked parent", () => {
    const sandbox = tempDir("repo-root-");
    const realParent = join(sandbox, "real-parent");
    const aliasParent = join(sandbox, "alias-parent");
    const otherCwd = join(sandbox, "other-cwd");
    mkdirSync(realParent);
    mkdirSync(otherCwd);
    symlinkSync(realParent, aliasParent, "dir");

    const repoRoot = join(aliasParent, "target-repo");
    const previousCwd = process.cwd();
    process.chdir(otherCwd);
    try {
      const result = scaffoldWorkspace({ repoRoot, template: "generic", component: "demo" });

      expect(result.status).toBe("created");
      expect(result.diagnostics).toEqual([]);
    } finally {
      process.chdir(previousCwd);
    }

    expect(existsSync(join(realParent, "target-repo", "use-cases.yml"))).toBe(true);
    expect(existsSync(join(realParent, "target-repo", "use-cases", "example.yml"))).toBe(true);
  });

  test("still rejects relative paths that climb outside the repo root", () => {
    const repoRoot = tempDir("escape-root-");

    try {
      resolveContainedPath(repoRoot, "../outside.yml", "Scaffold target escapes the repo boundary.");
      throw new Error("expected resolveContainedPath to reject an escaping path");
    } catch (error) {
      expect(error).toBeInstanceOf(UseCasesPluginError);
      expect((error as UseCasesPluginError).code).toBe("path.escape");
      expect((error as Error).message).toBe("Scaffold target escapes the repo boundary.");
    }
  });
});
