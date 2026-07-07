#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(here, "..");
const packageName = "Use Cases";
const copilotHookFile = "use-cases.json";
const env = process.env;

const hosts = new Set(
  (env.AGENT_HOOK_HOSTS ?? "claude,codex,opencode,copilot")
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean),
);

function truthy(value) {
  return value === "1" || value === "true" || value === "yes";
}

function disabled(value) {
  return value === "0" || value === "false" || value === "no";
}

function shouldInstall() {
  if (disabled(env.USE_CASES_INSTALL_AGENT_HOOKS) || disabled(env.AGENT_HOOKS_INSTALL)) return false;
  if (truthy(env.USE_CASES_INSTALL_AGENT_HOOKS) || truthy(env.AGENT_HOOKS_INSTALL)) return true;
  return env.npm_config_global === "true" || env.npm_config_location === "global";
}

function readJson(path, fallback) {
  if (!existsSync(path)) return fallback;
  const text = readFileSync(path, "utf8").trim();
  if (text.length === 0) return fallback;
  return JSON.parse(text);
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function shellQuote(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function sessionScript() {
  return resolve(packageRoot, "hooks/session-start");
}

function sessionCommand() {
  return `CLAUDE_PLUGIN_ROOT=${shellQuote(packageRoot)} bash ${shellQuote(sessionScript())}`;
}

function copilotSessionCommand() {
  return `COPILOT_CLI=1 ${sessionCommand()}`;
}

function isPackageHookCommand(hook) {
  const command = hook?.command;
  if (typeof command !== "string") return false;
  if (command.includes(sessionScript())) return true;

  return hook?.statusMessage === `Loading ${packageName} bootstrap` && command.includes("/hooks/session-start");
}

function removePackageHookCommands(sessionStart) {
  for (const entry of sessionStart) {
    if (!entry || typeof entry !== "object" || !Array.isArray(entry.hooks)) continue;
    entry.hooks = entry.hooks.filter((hook) => !isPackageHookCommand(hook));
  }

  return sessionStart.filter((entry) => {
    if (!entry || typeof entry !== "object") return false;
    if (!Array.isArray(entry.hooks)) return true;
    return entry.hooks.length > 0;
  });
}

function installSessionStartHook(path, matcher, statusMessage) {
  const config = readJson(path, {});
  config.hooks = config.hooks && typeof config.hooks === "object" ? config.hooks : {};
  const command = sessionCommand();
  const existing = Array.isArray(config.hooks.SessionStart) ? config.hooks.SessionStart : [];
  const sessionStart = removePackageHookCommands(existing);
  let entry = sessionStart.find((candidate) => candidate?.matcher === matcher && Array.isArray(candidate.hooks));

  if (!entry) {
    entry = { matcher, hooks: [] };
    sessionStart.push(entry);
  }

  entry.hooks.push({
    type: "command",
    command,
    async: false,
    timeout: 5,
    statusMessage,
  });

  config.hooks.SessionStart = sessionStart;
  writeJson(path, config);
}

function samePluginEntry(entry, pluginPath) {
  if (typeof entry === "string") return entry === pluginPath;
  if (Array.isArray(entry) && typeof entry[0] === "string") return entry[0] === pluginPath;
  return false;
}

function installOpenCodePlugin(path) {
  const config = readJson(path, { $schema: "https://opencode.ai/config.json" });
  const pluginPath = resolve(packageRoot, ".opencode/plugin/use-cases.js");
  const plugins = (Array.isArray(config.plugin) ? config.plugin : []).filter((entry) => {
    const value = Array.isArray(entry) ? entry[0] : entry;
    return typeof value !== "string" || !value.endsWith("/.opencode/plugin/use-cases.js");
  });

  if (!plugins.some((entry) => samePluginEntry(entry, pluginPath))) {
    plugins.push(pluginPath);
  }

  config.plugin = plugins;
  writeJson(path, config);
}

function copilotHooksRoot(home) {
  const copilotHome = env.COPILOT_HOME;
  return copilotHome ? resolve(copilotHome, "hooks") : resolve(home, ".copilot/hooks");
}

function installCopilotHook(path) {
  writeJson(path, {
    version: 1,
    hooks: {
      sessionStart: [
        {
          type: "command",
          bash: copilotSessionCommand(),
          timeoutSec: 5,
        },
      ],
    },
  });
}

function main() {
  if (!shouldInstall()) return;

  const home = env.HOME || homedir();
  if (!home) return;

  if (hosts.has("claude")) {
    installSessionStartHook(
      resolve(home, ".claude/settings.json"),
      "startup|clear|compact",
      `Loading ${packageName} bootstrap`,
    );
  }

  if (hosts.has("codex")) {
    installSessionStartHook(
      resolve(home, ".codex/hooks.json"),
      "startup|resume|clear|compact",
      `Loading ${packageName} bootstrap`,
    );
  }

  if (hosts.has("opencode")) {
    installOpenCodePlugin(resolve(home, ".config/opencode/opencode.json"));
  }

  if (hosts.has("copilot")) {
    installCopilotHook(resolve(copilotHooksRoot(home), copilotHookFile));
  }
}

try {
  main();
} catch (error) {
  console.error(`[${packageName}] agent hook install skipped: ${error instanceof Error ? error.message : String(error)}`);
}
