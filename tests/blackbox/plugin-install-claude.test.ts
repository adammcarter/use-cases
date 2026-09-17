// The black-box oracle for plugin.install.claude_from_github.
//
// The row is about what a host finds when it installs this repo, so the test
// inspects the SHIPPED manifests and layout. No product imports.
//
// Self-contained: a shared oracle file means one edit stales every row bound
// to it.
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

interface PluginManifest {
  name: string;
  version: string;
  agents?: string[];
  mcpServers?: Record<string, { command: string; args: string[] }>;
}

function manifest(dir = repoRoot): PluginManifest {
  return JSON.parse(readFileSync(join(dir, ".claude-plugin", "plugin.json"), "utf8")) as PluginManifest;
}

/** Every path a manifest declares, as it would resolve inside the plugin. */
function declaredPaths(m: PluginManifest): string[] {
  const paths = [...(m.agents ?? [])];
  for (const server of Object.values(m.mcpServers ?? {})) {
    for (const arg of server.args) {
      if (arg.includes("${CLAUDE_PLUGIN_ROOT}")) paths.push(arg.replace("${CLAUDE_PLUGIN_ROOT}/", "./"));
    }
  }
  return paths;
}

function missingPaths(dir: string, m: PluginManifest): string[] {
  return declaredPaths(m).filter((p) => !existsSync(join(dir, p.replace(/^\.\//, ""))));
}

//: @use-case:plugin.install.claude_from_github#blackbox
describe("plugin.install.claude_from_github", () => {
  // golden_manifests_point_at_real_files. Every declared path resolves, and the
  // MCP server is addressed through ${CLAUDE_PLUGIN_ROOT} so it works wherever
  // the host clones the plugin.
  test("every path the Claude manifest declares exists, and the MCP server is root-relative", () => {
    const m = manifest();

    expect(m.agents, "the manifest declares its agents explicitly").toBeTruthy();
    expect(missingPaths(repoRoot, m), "a declared path that does not exist would break the install").toEqual([]);

    const server = m.mcpServers?.["use-cases"];
    expect(server?.command).toBe("bash");
    expect(server?.args.join(" "), "addressed through the plugin root, not a relative path").toContain(
      "${CLAUDE_PLUGIN_ROOT}/bin/use-cases-mcp"
    );
    // The plugin's own entry point, executable in a fresh clone: the manifest
    // no longer names an interpreter and a bundle path, so what actually runs
    // is the plugin's decision and not the host's.
    expect(JSON.stringify(m), "no host manifest names the committed bundle").not.toContain("dist/uc");
    expect(statSync(join(repoRoot, "bin", "use-cases-mcp")).mode & 0o111, "the wrapper must be executable").not.toBe(0);

    // The hook is found by CONVENTION rather than declared in the manifest:
    // hooks/hooks.json is what wires SessionStart. A root Agent Plugins
    // manifest would make Copilot ignore it, which is why none ships.
    const hooks = JSON.parse(readFileSync(join(repoRoot, "hooks", "hooks.json"), "utf8")) as {
      hooks: { SessionStart: Array<{ hooks: Array<{ command: string }> }> };
    };
    expect(hooks.hooks.SessionStart[0].hooks[0].command).toContain("${CLAUDE_PLUGIN_ROOT}/hooks/session-start");
  });

  // bad_manifest_pointing_at_a_missing_file. The guard above is only worth
  // having if it would actually catch a break, so this proves it is not vacuous.
  test("a manifest pointing at a missing file is caught, not shipped", () => {
    const dir = mkdtempSync(join(tmpdir(), "uc-claude-install-"));
    tempDirs.push(dir);
    mkdirSync(join(dir, ".claude-plugin"), { recursive: true });
    cpSync(join(repoRoot, "agents"), join(dir, "agents"), { recursive: true });
    // The manifest also declares the MCP entry point, so the fixture needs a
    // stub for it — otherwise that path is missing too and the case stops
    // isolating the agent it is about.
    mkdirSync(join(dir, "bin"), { recursive: true });
    writeFileSync(join(dir, "bin", "use-cases-mcp"), "#!/usr/bin/env bash\n");

    const intact = { ...manifest(), agents: ["./agents/use-cases-updater.md"] };
    writeFileSync(join(dir, ".claude-plugin", "plugin.json"), JSON.stringify(intact));
    expect(missingPaths(dir, intact), "the fixture itself must start clean").toEqual([]);

    const broken = { ...intact, agents: ["./agents/use-cases-updater.md", "./agents/does-not-exist.md"] };
    writeFileSync(join(dir, ".claude-plugin", "plugin.json"), JSON.stringify(broken));
    expect(
      missingPaths(dir, broken),
      "the check must name the missing file rather than pass"
    ).toEqual(["./agents/does-not-exist.md"]);
  });

  // golden_marketplace_offers_the_repo_root. Without this the plugin manifest
  // is never read at all.
  test("the marketplace manifest offers this plugin from the repo root", () => {
    const market = JSON.parse(readFileSync(join(repoRoot, ".claude-plugin", "marketplace.json"), "utf8")) as {
      plugins: Array<{ name: string; source: string }>;
    };
    const offered = market.plugins.find((p) => p.name === "use-cases");
    expect(offered, "the marketplace must offer use-cases").toBeTruthy();
    expect(offered?.source, "the plugin IS the repo root").toBe(".");
  });

  // golden_skills_in_the_scanned_dir. Skills sit where Claude scans by default,
  // and each front-matter name matches its directory so the slash command is
  // /use-cases:<name>.
  test("the canonical skills sit in skills/ with front-matter names matching their directories", () => {
    const skills = readdirSync(join(repoRoot, "skills"));
    expect(skills.length).toBeGreaterThanOrEqual(4);

    for (const name of skills) {
      const body = readFileSync(join(repoRoot, "skills", name, "SKILL.md"), "utf8");
      const front = /^---\n([\s\S]*?)\n---\n/.exec(body);
      expect(front, `${name} must open with frontmatter`).not.toBeNull();
      const declared = /^name:\s*(.+)$/m.exec(front![1])?.[1]?.trim();
      expect(declared, `${name}: the front-matter name must match the directory`).toBe(name);
    }
  });

  // edge_live_session is NOT asserted here. It requires installing into Claude
  // Code and starting a session — a host observation, not something a test can
  // drive. It stays a scenario the owner watches rather than one the oracle
  // claims to cover.
  test.todo("edge_live_session — a host observation; cannot be driven from a test");
});
//: @use-case:end plugin.install.claude_from_github#blackbox
