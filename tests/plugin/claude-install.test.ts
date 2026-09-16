import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const CANONICAL_SKILLS = ["use-cases", "showcase", "walkthrough", "migration"];

function readJson(path: string): any {
  return JSON.parse(readFileSync(join(repoRoot, path), "utf8"));
}

//: @use-case:plugin.install.claude_from_github
describe("Claude Code installs the plugin straight from GitHub", () => {
  test("plugin.json points every entry at a real file and the bundle", () => {
    const manifest = readJson(".claude-plugin/plugin.json");
    expect(manifest.name).toBe("use-cases");
    for (const agent of manifest.agents as string[]) {
      expect(existsSync(join(repoRoot, agent)), agent).toBe(true);
    }
    const server = manifest.mcpServers["use-cases"];
    expect(server.command).toBe("node");
    expect(server.args).toEqual(["${CLAUDE_PLUGIN_ROOT}/dist/uc-mcp.js"]);
    expect(existsSync(join(repoRoot, "dist/uc-mcp.js"))).toBe(true);
    // Hooks come from the default hooks/hooks.json; it must exist and wire the script.
    const hooks = readJson("hooks/hooks.json");
    expect(JSON.stringify(hooks.hooks.SessionStart)).toContain("${CLAUDE_PLUGIN_ROOT}/hooks/session-start");
    expect(existsSync(join(repoRoot, "hooks/session-start"))).toBe(true);
  });

  test("marketplace.json offers use-cases from the repo root", () => {
    const marketplace = readJson(".claude-plugin/marketplace.json");
    expect(marketplace.name).toBe("use-cases");
    const entry = (marketplace.plugins as Array<{ name: string; source: string }>).find((p) => p.name === "use-cases");
    expect(entry?.source).toBe(".");
  });

  test("the canonical skills live in skills/ at the root, named for /use-cases:<name>", () => {
    for (const skill of CANONICAL_SKILLS) {
      const path = join(repoRoot, "skills", skill, "SKILL.md");
      expect(existsSync(path), path).toBe(true);
      const frontmatter = readFileSync(path, "utf8").match(/^---\n([\s\S]*?)\n---/)?.[1] ?? "";
      expect(frontmatter).toMatch(new RegExp(`^name: ${skill}$`, "m"));
    }
    // Nothing is left behind in the old, unscanned location.
    expect(existsSync(join(repoRoot, ".agents/skills"))).toBe(false);
    // And nothing else under skills/ lacks a SKILL.md.
    for (const dir of readdirSync(join(repoRoot, "skills"))) {
      expect(existsSync(join(repoRoot, "skills", dir, "SKILL.md")), dir).toBe(true);
    }
  });

  test.skip("live: two install commands give skills, agents and MCP tools on the next session", () => {
    // Performed by the user in Claude Code; recorded as showcase evidence, not here.
  });
});
//: @use-case:end plugin.install.claude_from_github
