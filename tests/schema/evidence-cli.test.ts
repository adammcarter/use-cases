import { cpSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../packages/core/src/schema/index.js";

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

describe("P3 evidence CLI", () => {
  test("records evidence and derives evidence status through schema-backed JSON", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = mkdtempSync(join(tmpdir(), "use-cases-evidence-cli-"));
    cpSync(join(repoRoot, "tests/fixtures/workspaces/evidence-basic"), workspaceRoot, {
      recursive: true
    });

    const record = run("node", [
      "packages/cli/dist/index.js",
      "evidence",
      "record",
      "--repo",
      workspaceRoot,
      "--use-case",
      "showcase.live.golden",
      "--kind",
      "manual_observation",
      "--result",
      "pass",
      "--json"
    ]);
    requireSuccess(record);
    const recordPayload = JSON.parse(record.stdout);
    expect(recordPayload).toMatchObject({
      command: "evidence.record",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        appended: true
      }
    });
    expect(
      validateBySchemaId(
        "https://use-cases.dev/schemas/v1/evidence-append-result.schema.json",
        recordPayload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });

    const status = run("node", [
      "packages/cli/dist/index.js",
      "evidence",
      "status",
      "--repo",
      workspaceRoot,
      "--json"
    ]);
    requireSuccess(status);
    const statusPayload = JSON.parse(status.stdout);
    expect(statusPayload).toMatchObject({
      command: "evidence.status",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        integrity: {
          state: "clean"
        },
        counts: {
          aggregates_active: 1
        }
      }
    });
    expect(
      validateBySchemaId(
        "https://use-cases.dev/schemas/v1/evidence-status-result.schema.json",
        statusPayload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });
  });
});
