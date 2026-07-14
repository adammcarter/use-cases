// Field report: "`showcase-runs/` litters the repo root, untracked, and isn't
// gitignored. It broke a merge's clean-working-tree gate."
//
// `uc init` scaffolds a workspace whose commands then write transient run output
// (showcase runs) and a transient verification-results ledger — but it never told
// git to ignore either, so the tool dirtied the adopter's working tree and tripped
// their own clean-tree gates. init now ensures those entries exist.
//
// Append-only and idempotent by construction: an adopter's existing .gitignore is
// never rewritten or reordered, only appended to, and only with entries it lacks.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";

function gitignoreOf(repoRoot: string): string {
  return readFileSync(join(repoRoot, ".gitignore"), "utf8");
}

describe("uc init keeps transient run output out of git", () => {
  let repoRoot: string;

  beforeEach(() => {
    repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-gitignore-"));
  });

  afterEach(() => {
    rmSync(repoRoot, { recursive: true, force: true });
  });

  test("creates a .gitignore covering the transient run output when none exists", () => {
    const result = scaffoldWorkspace({ repoRoot });

    expect(result.status).toBe("created");
    expect(existsSync(join(repoRoot, ".gitignore"))).toBe(true);
    const body = gitignoreOf(repoRoot);
    expect(body).toContain("showcase-runs/");
    expect(body).toContain(".use-cases/verification-results.jsonl");
    expect(result.created_files).toContain(".gitignore");
  });

  test("appends to an existing .gitignore without disturbing what is already there", () => {
    writeFileSync(join(repoRoot, ".gitignore"), "node_modules/\ndist/\n", "utf8");

    scaffoldWorkspace({ repoRoot });

    const body = gitignoreOf(repoRoot);
    // The adopter's own entries survive, in place.
    expect(body).toContain("node_modules/");
    expect(body).toContain("dist/");
    // …and ours are added.
    expect(body).toContain("showcase-runs/");
    expect(body).toContain(".use-cases/verification-results.jsonl");
  });

  test("is idempotent: re-running does not duplicate an entry it already added", () => {
    scaffoldWorkspace({ repoRoot });
    const first = gitignoreOf(repoRoot);

    scaffoldWorkspace({ repoRoot, force: true });
    const second = gitignoreOf(repoRoot);

    expect(second).toBe(first);
    expect(second.split("\n").filter((line) => line.trim() === "showcase-runs/")).toHaveLength(1);
  });

  test("respects an entry the adopter already wrote themselves", () => {
    writeFileSync(join(repoRoot, ".gitignore"), "showcase-runs/\n", "utf8");

    scaffoldWorkspace({ repoRoot });

    const lines = gitignoreOf(repoRoot)
      .split("\n")
      .filter((line) => line.trim() === "showcase-runs/");
    expect(lines).toHaveLength(1);
  });
});
