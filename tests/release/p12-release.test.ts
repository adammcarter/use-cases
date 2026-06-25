import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

describe("P12 release hardening", () => {
  test("doctor package verifies plugin contents, manifests, and forbidden paths", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = runCli(["doctor", "package", "--json"]);
    requireSuccess(result);
    const payload = JSON.parse(result.stdout);

    expect(payload).toMatchObject({
      command: "doctor.package",
      ok: true,
      complete: true,
      diagnostics: [],
      data: {
        complete: true,
        required_paths: expect.arrayContaining([
          expect.objectContaining({ path: ".codex-plugin/plugin.json", status: "present" }),
          expect.objectContaining({ path: ".mcp.json", status: "present" }),
          expect.objectContaining({ path: ".agents/skills/use-case-matrix/SKILL.md", status: "present" }),
          expect.objectContaining({ path: "packages/ucm-cli/dist/index.js", status: "present" }),
          expect.objectContaining({ path: "packages/ucm-mcp/dist/index.js", status: "present" }),
          expect.objectContaining({ path: "packages/ucm-core/dist/schemas/v1/use-case-file.schema.json", status: "present" })
        ]),
        forbidden_paths: [],
        manifest_references: expect.arrayContaining([
          expect.objectContaining({ from: ".codex-plugin/plugin.json", target: ".mcp.json", status: "resolved" }),
          expect.objectContaining({ from: ".mcp.json", target: "packages/ucm-mcp/dist/index.js", status: "resolved" })
        ])
      }
    });
  });

  test("root dry-run package contains built plugin assets and omits local/test state", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = run("corepack", ["pnpm", "pack", "--dry-run"]);
    requireSuccess(result);

    for (const included of [
      ".agents/skills/use-case-matrix/SKILL.md",
      ".codex-plugin/plugin.json",
      ".mcp.json",
      "packages/ucm-cli/dist/index.js",
      "packages/ucm-core/dist/schemas/v1/use-case-file.schema.json",
      "packages/ucm-mcp/dist/index.js",
      "README.md",
      "docs/release.md",
      "CHANGELOG.md"
    ]) {
      expect(result.stdout).toContain(included);
    }
    for (const forbidden of [
      "tests/",
      "packages/ucm-cli/src/",
      "packages/ucm-core/src/",
      "packages/ucm-mcp/src/",
      ".albus/",
      ".cowork-receipts/",
      ".copy-schemas.lock"
    ]) {
      expect(result.stdout).not.toContain(forbidden);
    }
  });

  test("release docs cover workflows, data, trust, hosts, and release checks", () => {
    for (const file of [
      "README.md",
      "docs/cli.md",
      "docs/data-model.md",
      "docs/showcase.md",
      "docs/hosts.md",
      "docs/security.md",
      "docs/release.md",
      "CHANGELOG.md"
    ]) {
      expect(readFileSync(join(repoRoot, file), "utf8")).not.toContain("[TODO");
    }

    const readme = readFileSync(join(repoRoot, "README.md"), "utf8");
    for (const workflow of ["continuous", "backfill", "showcase-only", "audit-only", "migration"]) {
      expect(readme).toContain(workflow);
    }

    expect(readFileSync(join(repoRoot, "docs", "security.md"), "utf8")).toContain("trusted user");
    expect(readFileSync(join(repoRoot, "docs", "hosts.md"), "utf8")).toContain("not_run");
    expect(readFileSync(join(repoRoot, "docs", "release.md"), "utf8")).toContain("doctor package");
  });
});

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run("node", ["packages/ucm-cli/dist/index.js", ...args]);
}

function run(command: string, args: string[], cwd = repoRoot): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd,
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
