import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { parseYamlToJson } from "../../packages/core/src/schema/index.js";
import { CANONICAL_SKILLS } from "../../packages/core/src/skills/canonicalSkills.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const skillRoot = join(repoRoot, ".agents", "skills");
// Bound to the single source of truth, so this test guards that host projection
// and skill validation (which both read CANONICAL_SKILLS) cover every shipped
// skill — including `migration`, which host projection once silently dropped.
const canonicalSkillNames = [...CANONICAL_SKILLS];
const knownCliCommands = new Set([
  "capsule list",
  "capsule plan",
  "capsule validate",
  "doctor roots",
  "doctor skills",
  "evidence record",
  "evidence status",
  "evidence void",
  "matrix list",
  "matrix remove",
  "matrix status",
  "matrix upsert",
  "matrix validate",
  "plan showcase",
  "plan walkthrough",
  "showcase approve",
  "showcase correct",
  "showcase decide",
  "showcase finish",
  "showcase pause",
  "showcase record-observation",
  "showcase record-verdict",
  "showcase reject",
  "showcase resume",
  "showcase start",
  "showcase status",
  "workflow mode",
  "workflow set-mode"
]);
// Flat, single-segment marker / keyless-tier commands. A reference like
// `uc bind --repo ...` carries a flag as its second token, so it is validated by
// its bare command name (mirrors validateSkillAssets.KNOWN_FLAT_CLI_COMMANDS).
const knownFlatCliCommands = new Set([
  "init",
  "bind",
  "scan",
  "verify",
  "recover",
  "keygen",
  "prove",
  "validate-ledger",
  "approve-run"
]);

describe("P7 canonical skills and activation bootstrap", () => {
  test("every canonical skill has valid frontmatter and a matching directory name", () => {
    expect(readdirSync(skillRoot).sort()).toEqual([...canonicalSkillNames].sort());
    const names = new Set<string>();
    for (const skillName of canonicalSkillNames) {
      const skillPath = join(skillRoot, skillName, "SKILL.md");
      expect(existsSync(skillPath)).toBe(true);
      const frontmatter = parseFrontmatter(readFileSync(skillPath, "utf8"), skillPath);
      expect(frontmatter.name).toBe(skillName);
      expect(String(frontmatter.description)).toMatch(/\b(use|Use|when|When)\b/);
      expect(String(frontmatter.description).length).toBeGreaterThan(40);
      expect(names.has(frontmatter.name)).toBe(false);
      names.add(frontmatter.name);
    }
  });

  test("skills reference only CLI commands that exist", () => {
    const references = canonicalSkillNames.flatMap((skillName) =>
      extractCliCommands(readFileSync(join(skillRoot, skillName, "SKILL.md"), "utf8"))
    );
    expect(references.length).toBeGreaterThan(0);
    for (const reference of references) {
      const bare = reference.split(/\s+/)[0];
      expect(knownCliCommands.has(reference) || knownFlatCliCommands.has(bare)).toBe(true);
    }
  });

  test("bootstrap contains activation, non-activation, trust, lifecycle, command, and claim boundaries", () => {
    const source = readFileSync(join(repoRoot, "bootstrap", "use-cases.md"), "utf8");
    for (const heading of [
      "When to apply",
      "When not to apply",
      "Trusted boundaries",
      "Default lifecycle",
      "Core commands",
      "Never claim"
    ]) {
      expect(source).toContain(heading);
    }
    expect(source).toContain("repo data");
    expect(source).toContain("MCP output");
    expect(source).toContain("generated runbooks");
    expect(source).toContain("secrets");
    expect(source).toContain("private data");
  });

  test("skills do not over-enforce showcase, proof, approval, or host support claims", () => {
    const combined = canonicalSkillNames
      .map((skillName) => readFileSync(join(skillRoot, skillName, "SKILL.md"), "utf8"))
      .join("\n");
    expect(combined).not.toMatch(/showcase\s+is\s+mandatory/i);
    expect(combined).not.toMatch(/required\s+showcase\s+for\s+all\s+work/i);
    expect(combined).not.toMatch(/generated\s+(plan|walkthrough|capsule|runbook)\s+is\s+proof/i);
    expect(combined).not.toMatch(/agents?\s+may\s+(claim|record)\s+(user approval|user sign-off)/i);
    expect(combined).not.toMatch(/\bhost\s+support\s+is\s+verified\./i);
  });

  //: @use-case:skills.assets.demo_gates
  test("showcase skill gates live demos on explicit user answers", () => {
    const source = readFileSync(join(skillRoot, "showcase", "SKILL.md"), "utf8");
    expect(source).toContain("## The Demo Card Loop");
    // The card is the demo; the question is only its confirm button.
    expect(source).toMatch(/card is the demo/i);
    // Gate 1: a live run starts only after the user says they are ready.
    expect(source).toMatch(/Gate 1[\s\S]{0,300}ready/i);
    expect(source).toMatch(/never start from inference/i);
    // Gate 2: driver choice, agent-driven offered only when genuinely executable.
    expect(source).toMatch(/Gate 2[\s\S]{0,200}who drives/i);
    // Gate 3: the fixed verdict in the fixed order, with optional notes.
    expect(source).toMatch(/Approve, Reject, Run it again/);
    expect(source).toMatch(/notes/i);
    // Atomicity: card text and question tool call share ONE message; a retry
    // re-composes the whole turn (card first), never re-asks a bare question.
    expect(source).toMatch(/SAME message/);
    expect(source).toMatch(/re-composes the whole turn/i);
    // The card grows across turns (Actual appended); reprints stand alone.
    expect(source).toMatch(/\*\*Actual\*\*/);
    expect(source).toMatch(/card grows/i);
    // The gates change HOW the answer is collected, never what it is worth:
    // no signed-tier plumbing in the everyday flow, and the F3 path stays the
    // separate opt-in release/audit gate.
    expect(source).toMatch(/a tap, not typed text/i);
    expect(source).toMatch(/opt-in release\/audit path/i);
    // Reject carries the user's decision + notes through the reject command.
    expect(source).toContain("`uc showcase reject");
    // The gates never soften the F3 boundary this file already guards below.
    expect(source).toMatch(/explicit/i);
  });
  //: @use-case:end skills.assets.demo_gates

  test("activation docs include an ASCII skill-selection decision tree", () => {
    const source = readFileSync(join(repoRoot, "docs", "activation.md"), "utf8");
    expect(source).toContain("Decision Tree");
    expect(source).toContain("-> use-cases");
    expect(source).toContain("-> showcase");
    expect(source).toContain("-> walkthrough");
    expect(source).toContain("-> do not activate");
  });

  test("doctor skills validates canonical artifacts through the CLI", () => {
    const build = run("corepack", ["pnpm", "build"]);
    expect(build.status).toBe(0);
    const result = run("node", ["packages/cli/dist/index.js", "doctor", "skills", "--repo", repoRoot, "--json"]);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "doctor.skills",
      ok: true,
      data: {
        schema_version: 1,
        complete: true,
        skill_count: canonicalSkillNames.length,
        bootstrap: {
          complete: true
        }
      }
    });
  });
});

// The skills used to exist on disk and be invisible to every host: nothing
// declared `.agents/skills` to Claude, and the package was never installable as
// a plugin, so no agent could ever load the showcase protocol. These pin the
// two manifest facts that make the skills discoverable.
//: @use-case:skills.assets.host_declaration
describe("P7 skills are declared to the Claude host", () => {
  const claudeManifest = JSON.parse(readFileSync(join(repoRoot, ".claude-plugin", "plugin.json"), "utf8")) as {
    skills?: string | string[];
  };

  test("the Claude plugin manifest declares the non-default skills directory", () => {
    const declared = typeof claudeManifest.skills === "string" ? [claudeManifest.skills] : (claudeManifest.skills ?? []);
    // Claude only auto-scans `skills/` at plugin root. Ours live in
    // `.agents/skills`, so without an explicit entry they are never loaded.
    expect(declared.map((entry) => entry.replace(/\/$/, ""))).toContain("./.agents/skills");
  });

  test("the package ships a marketplace manifest so it can be installed as a plugin", () => {
    const marketplacePath = join(repoRoot, ".claude-plugin", "marketplace.json");
    expect(existsSync(marketplacePath)).toBe(true);
    const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8")) as {
      name?: string;
      plugins?: Array<{ name?: string; source?: string }>;
    };
    expect(marketplace.name).toBe("use-cases");
    expect(marketplace.plugins?.map((plugin) => plugin.name)).toContain("use-cases");
  });

  test("both shipped manifests stay on the same version", () => {
    const codex = JSON.parse(readFileSync(join(repoRoot, ".codex-plugin", "plugin.json"), "utf8")) as { version?: string };
    const claude = claudeManifest as unknown as { version?: string };
    expect(claude.version).toBe(codex.version);
  });
});
//: @use-case:end skills.assets.host_declaration

function parseFrontmatter(source: string, path: string): { name: string; description: string } {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    throw new Error(`missing frontmatter in ${path}`);
  }
  const parsed = parseYamlToJson(match[1], path);
  if (!parsed.ok) {
    throw new Error(`invalid frontmatter in ${path}: ${parsed.diagnostics.map((diagnostic) => diagnostic.message).join(", ")}`);
  }
  return parsed.value as { name: string; description: string };
}

function extractCliCommands(source: string): string[] {
  const commands: string[] = [];
  for (const match of source.matchAll(/`(?:uc|pnpm cli --)\s+([^`]+?)`/g)) {
    const tokens = match[1].trim().split(/\s+/);
    if (tokens.length >= 2) {
      commands.push(`${tokens[0]} ${tokens[1]}`);
    }
  }
  return commands;
}

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}
