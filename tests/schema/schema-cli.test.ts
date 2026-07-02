import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { PUBLIC_SCHEMA_IDS } from "../../packages/core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
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

describe("P1 schema CLI", () => {
  test("lists schemas through the normative CLI JSON envelope", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = run("node", [
      "packages/cli/dist/index.js",
      "schema",
      "list",
      "--json"
    ]);

    requireSuccess(result);
    expect(result.stderr).toBe("");
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      schema_version: 1,
      protocol_version: 1,
      command: "schema.list",
      ok: true,
      complete: true,
      diagnostics: [],
      context: {
        component_id: "use-case-matrix"
      }
    });
    expect(payload.data.schemas).toHaveLength(PUBLIC_SCHEMA_IDS.length);
  });

  test("validates fixture workspaces with complete=false diagnostics for damaged YAML", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = run("node", [
      "packages/cli/dist/index.js",
      "schema",
      "validate-fixtures",
      "--json",
      "--fixture",
      "tests/fixtures/workspaces/damaged-yaml"
    ]);

    requireSuccess(result);
    expect(result.stderr).toBe("");
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      schema_version: 1,
      protocol_version: 1,
      command: "schema.validate-fixtures",
      ok: false,
      complete: false
    });
    expect(payload.diagnostics).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: "parse_error",
          severity: "error",
          source_path: expect.stringContaining("malformed.yml")
        })
      ])
    );
  });
});
