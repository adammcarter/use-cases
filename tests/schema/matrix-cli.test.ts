import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../packages/ucm-core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]) {
  return run("node", ["packages/ucm-cli/dist/index.js", ...args]);
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

describe("P2 matrix CLI", () => {
  test("validates a clean matrix through the normative CLI envelope", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = runCli([
      "matrix",
      "validate",
      "--repo",
      "tests/fixtures/workspaces/minimal-valid",
      "--json"
    ]);

    requireSuccess(result);
    expect(result.stderr).toBe("");
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      schema_version: 1,
      protocol_version: 1,
      command: "matrix.validate",
      ok: true,
      complete: true,
      diagnostics: [],
      data: {
        schema_version: 1,
        integrity: {
          state: "clean",
          populated: true,
          blocking_diagnostic_count: 0
        }
      }
    });
    expect(
      validateBySchemaId(
        "https://presentation-skills.dev/schemas/v1/matrix-validation-result.schema.json",
        payload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });
  });

  test("reports damaged input as partial in non-strict mode and failed in strict mode", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const nonStrict = runCli([
      "matrix",
      "validate",
      "--repo",
      "tests/fixtures/workspaces/damaged-yaml",
      "--json"
    ]);
    requireSuccess(nonStrict);
    const nonStrictPayload = JSON.parse(nonStrict.stdout);
    expect(nonStrictPayload).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: false,
      data: {
        integrity: {
          state: "partial",
          populated: true
        }
      }
    });
    expect(nonStrictPayload.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "parse_error",
        source_path: "use-cases/malformed-use-case.yml"
      })
    );

    const strict = runCli([
      "matrix",
      "validate",
      "--repo",
      "tests/fixtures/workspaces/damaged-yaml",
      "--json",
      "--strict"
    ]);
    expect(strict.status).toBe(1);
    expect(strict.stderr).toBe("");
    expect(JSON.parse(strict.stdout)).toMatchObject({
      command: "matrix.validate",
      ok: false,
      complete: false
    });
  });

  test("lists critical addressable use cases and excludes duplicate IDs", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = runCli([
      "matrix",
      "list",
      "--repo",
      "tests/fixtures/workspaces/minimal-valid",
      "--value",
      "critical",
      "--json"
    ]);

    requireSuccess(result);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "matrix.list",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        use_cases: [
          {
            id: "auth.login.success",
            title: "Successful login",
            value_tier: "critical",
            source_path: "use-cases/auth-login.yml"
          }
        ]
      }
    });
    expect(
      validateBySchemaId(
        "https://presentation-skills.dev/schemas/v1/matrix-list-result.schema.json",
        payload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });
  });
});
