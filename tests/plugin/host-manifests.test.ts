import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const read = (path: string) => JSON.parse(readFileSync(join(repoRoot, path), "utf8"));
const claude = read(".claude-plugin/plugin.json");

//: @use-case:plugin.install.copilot_from_github
describe("Copilot CLI installs the plugin straight from GitHub", () => {
  test("no root Agent Plugins manifest ships; Copilot reads the Claude manifest and hook", () => {
    // A root plugin.json switches Copilot into a mode that ignores hooks/hooks.json,
    // and with it the bootstrap. Observed live 2026-09-16.
    expect(existsSync(join(repoRoot, "plugin.json"))).toBe(false);
    expect(existsSync(join(repoRoot, "mcp.json"))).toBe(false);
    expect(claude.mcpServers["use-cases"].args).toEqual(["${CLAUDE_PLUGIN_ROOT}/dist/uc-mcp.js"]);
    const hooks = read("hooks/hooks.json");
    expect(JSON.stringify(hooks.hooks.SessionStart)).toContain("${CLAUDE_PLUGIN_ROOT}/hooks/session-start");
  });

  test("the session-start hook delivers the bootstrap in Copilot's shape and in Claude's", () => {
    const run = (env: Record<string, string>) =>
      spawnSync("bash", [join(repoRoot, "hooks/session-start")], { encoding: "utf8", env: { ...process.env, CLAUDE_ENV_FILE: "", ...env } });
    const copilot = run({ COPILOT_CLI: "1" });
    expect(copilot.status, copilot.stderr).toBe(0);
    const copilotOut = JSON.parse(copilot.stdout);
    expect(copilotOut.hookSpecificOutput).toBeUndefined();
    expect(copilotOut.additionalContext).toContain("<EXTREMELY_IMPORTANT>");
    const plain = run({});
    const plainOut = JSON.parse(plain.stdout);
    expect(plainOut.hookSpecificOutput.additionalContext).toContain("<EXTREMELY_IMPORTANT>");
  });

  test.skip("live: copilot plugin install + copilot mcp enable give skills, bootstrap and tools", () => {
    // Performed 2026-09-16 against the worktree; recorded as showcase evidence, not here.
  });
});
//: @use-case:end plugin.install.copilot_from_github

//: @use-case:plugin.install.codex_from_github
describe("Codex installs the plugin from its marketplace", () => {
  test(".codex-plugin/plugin.json declares skills, MCP and the hook in Codex's own form", () => {
    const codex = read(".codex-plugin/plugin.json");
    expect(codex.name).toBe(claude.name);
    expect(codex.version).toBe(claude.version);
    expect(codex.skills).toBe("./skills/");
    expect(codex.mcpServers).toBe("./.codex-plugin/mcp.json");
    const sessionStart = codex.hooks.hooks.SessionStart;
    expect(JSON.stringify(sessionStart)).toContain("${PLUGIN_ROOT}/hooks/session-start");
    const mcp = read(".codex-plugin/mcp.json");
    expect(mcp.mcpServers["use-cases"]).toEqual({ command: "node", args: ["./dist/uc-mcp.js"], cwd: "." });
    // A root .mcp.json is workspace config to Copilot and overrides the plugin's
    // server there with a path that cannot resolve. Observed live 2026-09-16.
    expect(existsSync(join(repoRoot, ".mcp.json"))).toBe(false);
  });

  test.skip("live: skills listed as use-cases:<name>; MCP tools blocked by the usage cap until 2026-09-21", () => {});
});
//: @use-case:end plugin.install.codex_from_github
