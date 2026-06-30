import { cpSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
}, 120_000);

function run(command: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run("node", ["packages/cli/dist/index.js", ...args]);
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [`command failed with status ${result.status}`, `stdout:\n${result.stdout}`, `stderr:\n${result.stderr}`].join("\n")
    );
  }
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-plugin-human-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function isJson(stdout: string): boolean {
  return stdout.trimStart().startsWith("{");
}

describe("CLI commands run WITHOUT --json and render human-readable output", () => {
  let workspace: string;
  beforeAll(() => {
    workspace = fixtureWorkspace("minimal-valid");
  });

  test("`matrix validate` runs bare (not the unknown-command fallback)", () => {
    const result = runCli(["matrix", "validate", "--repo", workspace]);
    // Regression: previously this fell through to help with exit 2.
    expect(result.stdout).not.toContain("No recognized command");
    expect(result.status).not.toBe(2);
    expect(isJson(result.stdout)).toBe(false);
    expect(result.stdout.toLowerCase()).toContain("matrix");
  });

  test("`matrix list` renders the behaviours as human text and lists a known row", () => {
    const result = runCli(["matrix", "list", "--repo", workspace]);
    expect(result.status).toBe(0);
    expect(isJson(result.stdout)).toBe(false);
    expect(result.stdout).toContain("auth.login.success");
    // Steers the human toward the machine path without forcing it.
    expect(result.stdout).toContain("--json");
  });

  test("`plan showcase` renders a human plan, not the unknown-command fallback", () => {
    const result = runCli(["plan", "showcase", "--repo", workspace, "--max-items", "3"]);
    expect(result.stdout).not.toContain("No recognized command");
    expect(result.status).not.toBe(2);
    expect(isJson(result.stdout)).toBe(false);
  });

  test("the same command with --json still emits the machine envelope (regression guard)", () => {
    const result = runCli(["matrix", "list", "--repo", workspace, "--json"]);
    expect(result.status).toBe(0);
    expect(isJson(result.stdout)).toBe(true);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({ command: "matrix.list", ok: true });
  });

  test("an unknown command still falls through to the usage help", () => {
    const result = runCli(["totally", "bogus"]);
    expect(result.stdout + result.stderr).toContain("No recognized command");
  });
});
