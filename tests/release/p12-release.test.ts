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
          expect.objectContaining({ path: ".agents/skills/use-cases-plugin/SKILL.md", status: "present" }),
          expect.objectContaining({ path: "packages/cli/dist/index.js", status: "present" }),
          expect.objectContaining({ path: "packages/mcp/dist/index.js", status: "present" }),
          expect.objectContaining({ path: "packages/core/dist/schemas/v1/use-case-file.schema.json", status: "present" })
        ]),
        forbidden_paths: [],
        manifest_references: expect.arrayContaining([
          expect.objectContaining({ from: ".codex-plugin/plugin.json", target: ".mcp.json", status: "resolved" }),
          expect.objectContaining({ from: ".mcp.json", target: "packages/mcp/dist/index.js", status: "resolved" })
        ])
      }
    });
  });

  test("root dry-run package contains built plugin assets and omits local/test state", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));

    const result = run("corepack", ["pnpm", "pack", "--dry-run"]);
    requireSuccess(result);

    for (const included of [
      ".agents/skills/use-cases-plugin/SKILL.md",
      ".codex-plugin/plugin.json",
      ".mcp.json",
      "packages/cli/dist/index.js",
      "packages/core/dist/schemas/v1/use-case-file.schema.json",
      "packages/mcp/dist/index.js",
      "README.md",
      "docs/release.md",
      "CHANGELOG.md"
    ]) {
      expect(result.stdout).toContain(included);
    }
    // The example PROJECTS under examples/ legitimately ship their own src/ and
    // tests/ layout (e.g. examples/python-pytest), so exclude those lines before
    // asserting the repo's OWN sources/tests never leak. Every other forbidden
    // token (.agent-cache, .copy-schemas.lock, packages/*/src) is still checked fully.
    const nonExampleOutput = result.stdout
      .split("\n")
      .filter((line) => !line.includes("examples/"))
      .join("\n");
    for (const forbidden of [
      "tests/",
      "packages/cli/src/",
      "packages/core/src/",
      "packages/mcp/src/",
      ".agent-cache/",
      ".agent-receipts/",
      ".copy-schemas.lock"
    ]) {
      expect(nonExampleOutput).not.toContain(forbidden);
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
  return run("node", ["packages/cli/dist/index.js", ...args]);
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
