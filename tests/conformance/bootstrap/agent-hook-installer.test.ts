import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");
const installer = resolve(repoRoot, "scripts/install-agent-hooks.mjs");
const hookScript = resolve(repoRoot, "hooks/session-start");
const opencodePlugin = resolve(repoRoot, ".opencode/plugin/use-cases.js");
const copilotHook = join(".copilot", "hooks", "use-cases.json");
const staleHookScript = "/opt/homebrew/lib/node_modules/@adammcarter/use-cases/hooks/session-start";

const homes: string[] = [];

function makeHome(): string {
  const home = mkdtempSync(join(tmpdir(), "use-cases-agent-hooks-"));
  homes.push(home);
  return home;
}

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

function runInstaller(home: string, env: Record<string, string | undefined> = {}) {
  return spawnSync(process.execPath, [installer], {
    cwd: repoRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      HOME: home,
      npm_config_global: "true",
      npm_config_location: "global",
      ...env
    }
  });
}

function sessionHooks(config: Record<string, unknown>): Array<Record<string, unknown>> {
  const hooks = config["hooks"] as Record<string, unknown> | undefined;
  const sessionStart = hooks?.["SessionStart"];
  return Array.isArray(sessionStart) ? (sessionStart as Array<Record<string, unknown>>) : [];
}

function hookCommands(config: Record<string, unknown>): string[] {
  return sessionHooks(config).flatMap((entry) => {
    const hooks = entry["hooks"];
    if (!Array.isArray(hooks)) return [];
    return hooks.flatMap((hook) => {
      if (typeof hook !== "object" || hook === null) return [];
      const command = (hook as Record<string, unknown>)["command"];
      return typeof command === "string" ? [command] : [];
    });
  });
}

function copilotCommands(config: Record<string, unknown>): string[] {
  const hooks = config["hooks"] as Record<string, unknown> | undefined;
  const sessionStart = hooks?.["sessionStart"];
  if (!Array.isArray(sessionStart)) return [];

  return sessionStart.flatMap((hook) => {
    if (typeof hook !== "object" || hook === null) return [];
    const command = (hook as Record<string, unknown>)["bash"];
    return typeof command === "string" ? [command] : [];
  });
}

afterEach(() => {
  for (const home of homes.splice(0)) {
    rmSync(home, { recursive: true, force: true });
  }
});

describe("agent hook installer", () => {
  test("package manifest publishes the installer and runs it on postinstall", () => {
    const pkg = JSON.parse(readFileSync(resolve(repoRoot, "package.json"), "utf8")) as {
      files?: string[];
      scripts?: Record<string, string>;
    };

    expect(pkg.files).toContain("scripts/install-agent-hooks.mjs");
    expect(pkg.files).toContain(".opencode/plugin/use-cases.js");
    expect(pkg.scripts?.["postinstall"]).toBe("node scripts/install-agent-hooks.mjs");
  });

  test("local package installs do not mutate global host configs", () => {
    const home = makeHome();
    const result = runInstaller(home, {
      npm_config_global: "false",
      npm_config_location: "project"
    });

    expect(result.status).toBe(0);
    expect(existsSync(join(home, ".claude/settings.json"))).toBe(false);
    expect(existsSync(join(home, ".codex/hooks.json"))).toBe(false);
    expect(existsSync(join(home, ".config/opencode/opencode.json"))).toBe(false);
    expect(existsSync(join(home, copilotHook))).toBe(false);
  });

  test("global installs add Claude, Codex, OpenCode, and Copilot activation once", () => {
    const home = makeHome();
    const first = runInstaller(home);
    const second = runInstaller(home);

    expect(first.status).toBe(0);
    expect(first.stderr).toBe("");
    expect(second.status).toBe(0);
    expect(second.stderr).toBe("");

    const claude = readJson(join(home, ".claude/settings.json"));
    const codex = readJson(join(home, ".codex/hooks.json"));
    const opencode = readJson(join(home, ".config/opencode/opencode.json"));
    const copilot = readJson(join(home, copilotHook));

    const claudeCommands = hookCommands(claude);
    const codexCommands = hookCommands(codex);
    expect(claudeCommands.filter((command) => command.includes(hookScript))).toHaveLength(1);
    expect(codexCommands.filter((command) => command.includes(hookScript))).toHaveLength(1);
    expect(claudeCommands[0]).toContain("CLAUDE_PLUGIN_ROOT=");
    expect(claudeCommands[0]).toContain(" bash ");
    expect(codexCommands[0]).toContain("CLAUDE_PLUGIN_ROOT=");
    expect(codexCommands[0]).toContain(" bash ");
    expect(sessionHooks(claude).some((entry) => entry["matcher"] === "startup|clear|compact")).toBe(true);
    expect(sessionHooks(codex).some((entry) => entry["matcher"] === "startup|resume|clear|compact")).toBe(true);
    expect(opencode["plugin"]).toEqual([opencodePlugin]);
    expect(copilot["version"]).toBe(1);
    expect(copilotCommands(copilot)).toEqual([
      expect.stringContaining("COPILOT_CLI=1 CLAUDE_PLUGIN_ROOT=")
    ]);
    expect(copilotCommands(copilot)[0]).toContain(" bash ");
    expect(copilotCommands(copilot)[0]).toContain(hookScript);
  });

  test("existing host config is preserved while package-owned entries are deduped", () => {
    const home = makeHome();
    const claudeSettings = join(home, ".claude/settings.json");
    const codexHooks = join(home, ".codex/hooks.json");
    const opencodeConfig = join(home, ".config/opencode/opencode.json");
    const copilotConfig = join(home, copilotHook);
    mkdirSync(join(home, ".claude"), { recursive: true });
    mkdirSync(join(home, ".codex"), { recursive: true });
    mkdirSync(join(home, ".config/opencode"), { recursive: true });
    mkdirSync(dirname(copilotConfig), { recursive: true });

    writeFileSync(
      claudeSettings,
      JSON.stringify({
        model: "sonnet",
        hooks: {
          SessionStart: [
            {
              matcher: "startup|clear|compact",
              hooks: [
                { type: "command", command: "echo existing" },
                { type: "command", command: `CLAUDE_PLUGIN_ROOT=${repoRoot} ${hookScript}` },
                {
                  type: "command",
                  command: `CLAUDE_PLUGIN_ROOT='/opt/homebrew/lib/node_modules/@adammcarter/use-cases' '${staleHookScript}'`,
                  statusMessage: "Loading Use Cases bootstrap"
                }
              ]
            }
          ]
        }
      }),
      "utf8"
    );
    writeFileSync(
      codexHooks,
      JSON.stringify({
        hooks: {
          SessionStart: [
            {
              matcher: "startup|resume|clear|compact",
              hooks: [
                { type: "command", command: "echo existing" },
                { type: "command", command: `CLAUDE_PLUGIN_ROOT=${repoRoot} ${hookScript}` },
                {
                  type: "command",
                  command: `CLAUDE_PLUGIN_ROOT='/opt/homebrew/lib/node_modules/@adammcarter/use-cases' '${staleHookScript}'`,
                  statusMessage: "Loading Use Cases bootstrap"
                }
              ]
            }
          ]
        }
      }),
      "utf8"
    );
    writeFileSync(
      opencodeConfig,
      JSON.stringify({
        plugin: [
          "superpowers@git+https://github.com/obra/superpowers.git",
          "/tmp/old-use-cases/.opencode/plugin/use-cases.js"
        ]
      }),
      "utf8"
    );
    writeFileSync(
      copilotConfig,
      JSON.stringify({
        version: 1,
        hooks: {
          sessionStart: [
            { type: "command", bash: "echo stale use-cases" }
          ]
        }
      }),
      "utf8"
    );

    const result = runInstaller(home);

    expect(result.status).toBe(0);

    const claude = readJson(claudeSettings);
    const codex = readJson(codexHooks);
    const opencode = readJson(opencodeConfig);
    const copilot = readJson(copilotConfig);

    expect(claude["model"]).toBe("sonnet");
    expect(hookCommands(claude)).toContain("echo existing");
    expect(hookCommands(codex)).toContain("echo existing");
    expect(hookCommands(claude).filter((command) => command.includes(hookScript))).toHaveLength(1);
    expect(hookCommands(codex).filter((command) => command.includes(hookScript))).toHaveLength(1);
    expect(hookCommands(claude).filter((command) => command.includes(staleHookScript))).toHaveLength(0);
    expect(hookCommands(codex).filter((command) => command.includes(staleHookScript))).toHaveLength(0);
    expect(opencode["plugin"]).toEqual([
      "superpowers@git+https://github.com/obra/superpowers.git",
      opencodePlugin
    ]);
    expect(copilotCommands(copilot)).toHaveLength(1);
    expect(copilotCommands(copilot)[0]).toContain(hookScript);
  });
});
