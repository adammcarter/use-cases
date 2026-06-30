import { spawnSync } from "node:child_process";
import { cpSync, existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../../packages/core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]) {
  return run("node", ["packages/cli/dist/index.js", ...args]);
}

function requireSuccess(result: ReturnType<typeof run>) {
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

describe("P5 plan CLI contract", () => {
  test("generates showcase and walkthrough plans through read-only JSON commands", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("presentation-selection");
    const before = snapshotFiles(workspaceRoot);

    const showcase = runCli([
      "plan",
      "showcase",
      "--repo",
      workspaceRoot,
      "--timebox",
      "360",
      "--max-items",
      "2",
      "--host",
      "codex.cli",
      "--changed-path",
      "src/checkout/flow.ts",
      "--generated-at",
      "2026-06-25T12:00:00.000Z",
      "--json"
    ]);
    requireSuccess(showcase);
    expect(showcase.stderr).toBe("");
    expect(showcase.stdout.trim().split("\n")).toHaveLength(1);
    const showcasePayload = JSON.parse(showcase.stdout);
    expect(showcasePayload).toMatchObject({
      command: "plan.showcase",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        outcome: "generated",
        plan: {
          mode: "showcase",
          prepared_not_performed: true
        }
      }
    });
    expect(
      validateBySchemaId(
        "https://use-cases-plugin.dev/schemas/v1/presentation-plan-result.schema.json",
        showcasePayload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });

    const walkthrough = runCli([
      "plan",
      "walkthrough",
      "--repo",
      workspaceRoot,
      "--timebox",
      "1800",
      "--host",
      "codex.cli",
      "--generated-at",
      "2026-06-25T12:00:00.000Z",
      "--json"
    ]);
    requireSuccess(walkthrough);
    const walkthroughPayload = JSON.parse(walkthrough.stdout);
    expect(walkthroughPayload).toMatchObject({
      command: "plan.walkthrough",
      ok: true,
      complete: true,
      data: {
        outcome: "generated",
        plan: {
          mode: "walkthrough",
          prepared_not_performed: true
        }
      }
    });

    expect(snapshotFiles(workspaceRoot)).toEqual(before);
  });

  test("uses stable no-eligible and strict-partial exit semantics", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const noEligible = runCli([
      "plan",
      "showcase",
      "--repo",
      "tests/fixtures/workspaces/presentation-no-eligible",
      "--host",
      "codex.cli",
      "--json"
    ]);
    expect(noEligible.status).toBe(1);
    expect(JSON.parse(noEligible.stdout)).toMatchObject({
      command: "plan.showcase",
      ok: true,
      complete: true,
      data: {
        outcome: "no_eligible_items",
        plan: null
      }
    });

    const partialStrict = runCli([
      "plan",
      "showcase",
      "--repo",
      "tests/fixtures/workspaces/presentation-partial",
      "--host",
      "codex.cli",
      "--strict",
      "--json"
    ]);
    expect(partialStrict.status).toBe(3);
    expect(JSON.parse(partialStrict.stdout)).toMatchObject({
      command: "plan.showcase",
      ok: false,
      complete: false,
      data: {
        outcome: "integrity_blocked",
        plan: null
      }
    });
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-plugin-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function snapshotFiles(root: string): Record<string, string> {
  const files = listFiles(root);
  return Object.fromEntries(files.map((path) => [relative(root, path).replaceAll("\\", "/"), readFileSync(path, "utf8")]));
}

function listFiles(root: string): string[] {
  if (!existsSync(root)) {
    return [];
  }
  return readdirSync(root)
    .flatMap((name) => {
      const path = join(root, name);
      return statSync(path).isDirectory() ? listFiles(path) : [path];
    })
    .sort();
}
