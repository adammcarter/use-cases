import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
}, 30_000);

describe("P14 use-case mutation CLI", () => {
  test("adds, updates, and safely removes a use case in one feature file", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const useCaseId = "auth.login.password_reset";
    const created = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/auth-login.yml",
      "--use-case-json",
      JSON.stringify({
        id: useCaseId,
        title: "Password reset entry point",
        lifecycle: "planned",
        value_tier: "supporting",
        journey_role: "alternate",
        usage_frequency: "occasional",
        tags: ["auth", "login"]
      }),
      "--json"
    ]);

    requireSuccess(created);
    expect(JSON.parse(created.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: true,
      complete: true,
      data: {
        operation: "upsert",
        status: "created",
        use_case_id: useCaseId,
        file_path: "use-cases/auth-login.yml"
      }
    });

    const createdRow = listUseCase(workspaceRoot, useCaseId);
    expect(createdRow).toMatchObject({
      title: "Password reset entry point",
      lifecycle: "planned"
    });

    const updated = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/auth-login.yml",
      "--expected-hash",
      createdRow.semantic_hash,
      "--use-case-json",
      JSON.stringify({
        id: useCaseId,
        title: "Password reset recovery path",
        lifecycle: "planned",
        value_tier: "supporting",
        journey_role: "alternate",
        usage_frequency: "occasional",
        tags: ["auth", "recovery"]
      }),
      "--json"
    ]);

    requireSuccess(updated);
    expect(JSON.parse(updated.stdout)).toMatchObject({
      data: {
        status: "updated",
        before_hash: createdRow.semantic_hash
      }
    });
    expect(listUseCase(workspaceRoot, useCaseId)).toMatchObject({
      title: "Password reset recovery path",
      lifecycle: "planned",
      tags: ["auth", "recovery"]
    });

    const removed = runCli([
      "matrix",
      "remove",
      "--repo",
      workspaceRoot,
      "--use-case",
      useCaseId,
      "--reason",
      "Merged into another auth recovery path.",
      "--json"
    ]);

    requireSuccess(removed);
    expect(JSON.parse(removed.stdout)).toMatchObject({
      command: "matrix.remove",
      ok: true,
      complete: true,
      data: {
        operation: "remove",
        status: "removed",
        use_case_id: useCaseId
      }
    });
    const removedRow = listUseCase(workspaceRoot, useCaseId, "removed");
    expect(removedRow).toMatchObject({
      lifecycle: "removed"
    });
    const fileText = readFileSync(join(workspaceRoot, "use-cases/auth-login.yml"), "utf8");
    expect(fileText).toContain("Merged into another auth recovery path.");
  });

  test("blocks mutation when the matrix is incomplete", () => {
    const workspaceRoot = fixtureWorkspace("damaged-yaml");
    const result = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "use-cases/valid-use-case.yml",
      "--use-case-json",
      JSON.stringify({
        id: "damaged.new.case",
        title: "Should not write through damaged matrix",
        lifecycle: "planned",
        value_tier: "supporting",
        journey_role: "edge",
        usage_frequency: "rare"
      }),
      "--json"
    ]);

    expect(result.status).toBe(1);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      complete: false,
      diagnostics: [expect.objectContaining({ code: "matrix.mutation_incomplete_matrix" })]
    });
  });

  test("rejects target file paths outside use-cases", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const result = runCli([
      "matrix",
      "upsert",
      "--repo",
      workspaceRoot,
      "--file",
      "../escape.yml",
      "--use-case-json",
      JSON.stringify({
        id: "escape.case",
        title: "Escaping case",
        lifecycle: "planned",
        value_tier: "supporting",
        journey_role: "edge",
        usage_frequency: "rare"
      }),
      "--json"
    ]);

    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      complete: false,
      diagnostics: [expect.objectContaining({ code: "matrix.mutation_path_escape" })]
    });
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function listUseCase(workspaceRoot: string, useCaseId: string, lifecycle = "planned"): Record<string, unknown> {
  const result = runCli(["matrix", "list", "--repo", workspaceRoot, "--lifecycle", lifecycle, "--json"]);
  requireSuccess(result);
  const payload = JSON.parse(result.stdout) as { data: { use_cases: Array<Record<string, unknown>> } };
  const row = payload.data.use_cases.find((item) => item.id === useCaseId);
  if (!row) {
    throw new Error(`use case not found: ${useCaseId}`);
  }
  return row;
}

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run("node", ["packages/cli/dist/index.js", ...args]);
}

function run(command: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [
        `command failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}
