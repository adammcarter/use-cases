import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { validateSkillAssets } from "../../src/skills/validateSkillAssets.js";
import type { ResolvedWorkspaceContext } from "../../src/roots.js";

const repoRoot = resolve(import.meta.dirname, "../../../..");
const temporaryRoots: string[] = [];

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) {
    rmSync(root, { force: true, recursive: true });
  }
});

// A copy of the real plugin checkout, so the fixture drifts with the product
// instead of encoding a frozen snapshot of it.
function pluginCheckout(): string {
  const root = mkdtempSync(join(tmpdir(), "uc-skill-registration-"));
  temporaryRoots.push(root);
  for (const entry of [".agents", ".claude-plugin", "bootstrap", "docs"]) {
    cpSync(join(repoRoot, entry), join(root, entry), { recursive: true });
  }
  return root;
}

function contextFor(root: string): ResolvedWorkspaceContext {
  return {
    plugin_root: root,
    workspace_root: root,
    data_root: join(root, ".use-cases"),
    use_cases_root: join(root, "use-cases"),
    component_id: "use-cases",
    config_path: null,
    verifiers: { default: null, byId: {} }
  } as unknown as ResolvedWorkspaceContext;
}

function codesFor(root: string): string[] {
  return validateSkillAssets({ context: contextFor(root) }).diagnostics.map((diagnostic) => diagnostic.code);
}

describe("skill host registration", () => {
  test("an intact plugin checkout reports the skills as registered", () => {
    const root = pluginCheckout();
    const result = validateSkillAssets({ context: contextFor(root) });
    expect(result.diagnostics.filter((diagnostic) => diagnostic.severity === "error")).toEqual([]);
    expect(result.host_registration).toMatchObject({
      complete: true,
      hosts: [{ host: "claude", declares_skill_root: true, installable: true }]
    });
  });

  // THE REGRESSION THIS EXISTS FOR: skills present on disk, doctor green,
  // and no agent could load them, because nothing declared the directory.
  test("skills present on disk but undeclared to the host are an error, not a pass", () => {
    const root = pluginCheckout();
    const manifestPath = join(root, ".claude-plugin", "plugin.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Record<string, unknown>;
    delete manifest.skills;
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

    expect(codesFor(root)).toContain("skills.host_not_declared");
    expect(validateSkillAssets({ context: contextFor(root) }).complete).toBe(false);
  });

  test("a manifest pointing at the wrong directory does not count as declared", () => {
    const root = pluginCheckout();
    const manifestPath = join(root, ".claude-plugin", "plugin.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Record<string, unknown>;
    manifest.skills = ["./skills/"];
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

    expect(codesFor(root)).toContain("skills.host_not_declared");
  });

  test("a declared skill root is still unreachable without a marketplace manifest", () => {
    const root = pluginCheckout();
    rmSync(join(root, ".claude-plugin", "marketplace.json"));

    expect(codesFor(root)).toContain("skills.host_not_installable");
  });

  test("a marketplace that omits the plugin does not make it installable", () => {
    const root = pluginCheckout();
    const marketplacePath = join(root, ".claude-plugin", "marketplace.json");
    const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8")) as Record<string, unknown>;
    marketplace.plugins = [{ name: "something-else", source: "./" }];
    writeFileSync(marketplacePath, `${JSON.stringify(marketplace, null, 2)}\n`);

    expect(codesFor(root)).toContain("skills.host_not_installable");
  });
});
