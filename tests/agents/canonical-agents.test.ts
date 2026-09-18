import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { parseYamlToJson } from "../../packages/core/src/schema/index.js";
import { CANONICAL_AGENTS } from "../../packages/core/src/agents/canonicalAgents.js";
// The commands an agent body may reference. Shared with validateSkillAssets and
// parity-tested against the CLI registry, so an agent can cite any real command.
import {
  KNOWN_CLI_COMMANDS as knownCliCommands,
  KNOWN_FLAT_CLI_COMMANDS as knownFlatCliCommands
} from "../../packages/core/src/cli/knownCommands.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const agentRoot = join(repoRoot, "agents");

// Mirrors the skills surface: one list is the single source of truth, so a new
// agent cannot be shipped on one host and silently dropped from another. The
// skills equivalent (`migration`) was once dropped exactly this way.
const canonicalAgentNames = [...CANONICAL_AGENTS];


function readAgent(name: string): string {
  return readFileSync(join(agentRoot, `${name}.md`), "utf8");
}

function frontmatterOf(source: string): { name?: unknown; description?: unknown } {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  expect(match, "agent must open with YAML frontmatter").not.toBeNull();
  const parsed = parseYamlToJson(match![1], "agent");
  expect(parsed.ok).toBe(true);
  return parsed.value as { name?: unknown; description?: unknown };
}

describe("canonical agents", () => {
//: @use-case:agents.roster.shipped_with_plugin
  test("the agents directory holds exactly the canonical agents", () => {
    expect(existsSync(agentRoot)).toBe(true);
    const files = readdirSync(agentRoot).filter((entry) => entry.endsWith(".md")).sort();
    expect(files).toEqual([...canonicalAgentNames].map((name) => `${name}.md`).sort());
  });
//: @use-case:end agents.roster.shipped_with_plugin

  test.each(canonicalAgentNames)("%s has frontmatter whose name matches its filename", (name) => {
    const frontmatter = frontmatterOf(readAgent(name));
    expect(frontmatter.name).toBe(name);
  });

  test.each(canonicalAgentNames)("%s has a description specific enough to route on", (name) => {
    const description = frontmatterOf(readAgent(name)).description;
    expect(typeof description).toBe("string");
    // A description is a trigger string. A bare restatement of the name tells the
    // dispatching agent nothing about when to reach for it.
    expect(String(description).length).toBeGreaterThanOrEqual(40);
    expect(String(description).trim()).not.toBe(name);
  });

  test.each(canonicalAgentNames)("%s references only CLI commands the plugin ships", (name) => {
    const source = readAgent(name);
    const unknown: string[] = [];
    for (const match of source.matchAll(/`(?:use-cases|pnpm cli --)\s+([^`]+?)`/g)) {
      const tokens = match[1].trim().split(/\s+/);
      const [first, second] = tokens;
      if (!second || second.startsWith("-")) {
        if (!knownFlatCliCommands.has(first)) {
          unknown.push(first);
        }
        continue;
      }
      if (!knownCliCommands.has(`${first} ${second}`) && !knownFlatCliCommands.has(first)) {
        unknown.push(`${first} ${second}`);
      }
    }
    expect(unknown).toEqual([]);
  });

//: @use-case:agents.roster.bodies_hold_the_line#bodies
  test.each(canonicalAgentNames)("%s never authorises an agent to claim the user's approval", (name) => {
    const source = readAgent(name);
    expect(source).not.toMatch(/agents?\s+may\s+(claim|record)\s+(user approval|user sign-off)/i);
    expect(source).not.toMatch(/generated\s+(plan|walkthrough|capsule|runbook)\s+is\s+proof/i);
    expect(source).not.toMatch(/\bhost\s+support\s+is\s+verified\./i);
  });

  test.each(canonicalAgentNames)("%s speaks to this plugin's users, not to one private setup", (name) => {
    const source = readAgent(name);
    // Agent bodies ship to everyone who installs the plugin. A reference to the
    // author's own machine, roster, or sibling repo is meaningless to them.
    expect(source).not.toMatch(/agent-setup|~\/\.claude|\/Users\//);
//: @use-case:end agents.roster.bodies_hold_the_line#bodies
  });

  // The installer rejects a DIRECTORY here ("agents: Invalid input") and takes the
  // whole plugin down with it — every skill, hook and MCP server included. It shows
  // up only as "1 error during load", so the plugin silently stays uninstalled.
  // `skills` next to it DOES take a directory, which is what made this easy to miss.
  test("the Claude plugin manifest declares each agent as a file path", () => {
    const manifest = JSON.parse(readFileSync(join(repoRoot, ".claude-plugin", "plugin.json"), "utf8")) as {
      agents?: unknown;
    };
    expect(Array.isArray(manifest.agents)).toBe(true);
    const entries = manifest.agents as string[];
    expect(entries.length).toBeGreaterThan(0);
    for (const entry of entries) {
      expect(entry.endsWith(".md")).toBe(true);
      expect(existsSync(join(repoRoot, entry))).toBe(true);
    }
  });
});
