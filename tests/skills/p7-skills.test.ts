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
// `ucm bind --repo ...` carries a flag as its second token, so it is validated by
// its bare command name (mirrors validateSkillAssets.KNOWN_FLAT_CLI_COMMANDS).
const knownFlatCliCommands = new Set([
  "init",
  "bind",
  "scan",
  "verify",
  "recover",
  "keygen",
  "prove",
  "validate-ledger"
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
    const source = readFileSync(join(repoRoot, "bootstrap", "use-case-matrix.md"), "utf8");
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

  test("activation docs include an ASCII skill-selection decision tree", () => {
    const source = readFileSync(join(repoRoot, "docs", "activation.md"), "utf8");
    expect(source).toContain("Decision Tree");
    expect(source).toContain("-> use-case-matrix");
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
  for (const match of source.matchAll(/`(?:ucm|pnpm cli --)\s+([^`]+?)`/g)) {
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
