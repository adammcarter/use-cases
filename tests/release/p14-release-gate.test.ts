import { existsSync, readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { PACKAGE_VERSION } from "../helpers/package-version";

describe("P14 production release gate", () => {
  test("CI runs the same sequential release gate used locally", () => {
    expect(existsSync("scripts/release-gate.mjs")).toBe(true);
    expect(existsSync(".github/workflows/ci.yml")).toBe(true);

    const gate = readFileSync("scripts/release-gate.mjs", "utf8");
    const workflow = readFileSync(".github/workflows/ci.yml", "utf8");

    const buildIndex = gate.indexOf("corepack pnpm build");
    const testIndex = gate.indexOf("corepack pnpm test");

    expect(workflow).toContain("node scripts/release-gate.mjs");
    expect(gate).toContain("corepack pnpm install --frozen-lockfile");
    expect(gate).toContain("corepack pnpm typecheck");
    expect(gate).toContain("corepack pnpm build");
    expect(gate).toContain("corepack pnpm test");
    expect(gate).toContain("corepack pnpm cli -- doctor package --json");
    expect(gate).toContain("corepack pnpm cli -- matrix validate --repo . --json");
    expect(gate).toContain("corepack pnpm cli -- matrix list --repo . --json");
    expect(gate).toContain("corepack pnpm pack --json --pack-destination");
    expect(buildIndex).toBeGreaterThan(-1);
    expect(testIndex).toBeGreaterThan(buildIndex);
  });

  test("root package is marked as a publishable package", () => {
    const manifest = JSON.parse(readFileSync("package.json", "utf8")) as {
      version: string;
      private?: boolean;
      files: string[];
    };

    expect(manifest.version).toBe(PACKAGE_VERSION);
    expect(manifest.private).toBe(false);
    expect(manifest.files).toContain("packages/cli/dist");
    expect(manifest.files).toContain("packages/mcp/dist");
    expect(manifest.files).toContain("schemas/v1");
  });

  test("all published version surfaces report the same version", () => {
    const rootManifest = JSON.parse(readFileSync("package.json", "utf8")) as { version: string };
    const cliManifest = JSON.parse(readFileSync("packages/cli/package.json", "utf8")) as { version: string };
    const coreManifest = JSON.parse(readFileSync("packages/core/package.json", "utf8")) as { version: string };
    const mcpManifest = JSON.parse(readFileSync("packages/mcp/package.json", "utf8")) as { version: string };
    const rootPlugin = JSON.parse(readFileSync("plugin.json", "utf8")) as { version: string };
    const codexPlugin = JSON.parse(readFileSync(".codex-plugin/plugin.json", "utf8")) as { version: string };
    const claudePlugin = JSON.parse(readFileSync(".claude-plugin/plugin.json", "utf8")) as { version: string };
    const versionSource = readFileSync("packages/core/src/version.ts", "utf8");
    const hostProjection = readFileSync("packages/core/src/hosts/projectHostFiles.ts", "utf8");
    const changelog = readFileSync("CHANGELOG.md", "utf8");

    expect(rootManifest.version).toBe(PACKAGE_VERSION);
    expect(cliManifest.version).toBe(rootManifest.version);
    expect(coreManifest.version).toBe(rootManifest.version);
    expect(mcpManifest.version).toBe(rootManifest.version);
    expect(rootPlugin.version).toBe(rootManifest.version);
    expect(codexPlugin.version).toBe(rootManifest.version);
    expect(claudePlugin.version).toBe(rootManifest.version);
    expect(versionSource).toContain(`UCM_VERSION = "${PACKAGE_VERSION}"`);
    expect(hostProjection).toContain("plugin_version: UCM_VERSION");
    expect(changelog).toContain(`## ${PACKAGE_VERSION}`);
  });
});
