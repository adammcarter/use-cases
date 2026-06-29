import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, sep } from "node:path";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { parseYamlToJson, type Diagnostic } from "../schema/index.js";
import type { SkillAssetSummary, SkillAssetValidationResult, SkillCommandReference } from "./types.js";

const CANONICAL_SKILLS = ["use-cases-plugin", "showcase", "walkthrough"] as const;
const BOOTSTRAP_SECTIONS = [
  "When to apply",
  "When not to apply",
  "Trusted boundaries",
  "Default lifecycle",
  "Core commands",
  "Never claim"
] as const;
const KNOWN_CLI_COMMANDS = new Set([
  "capsule list",
  "capsule plan",
  "capsule validate",
  "doctor roots",
  "doctor skills",
  "evidence record",
  "evidence status",
  "evidence void",
  "matrix list",
  "matrix status",
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
const FORBIDDEN_PATTERNS: Array<{ code: string; pattern: RegExp; message: string }> = [
  {
    code: "skills.mandatory_showcase_claim",
    pattern: /showcase\s+is\s+mandatory|required\s+showcase\s+for\s+all\s+work/i,
    message: "Skill text must not make showcase mandatory for all work."
  },
  {
    code: "skills.generated_material_claim",
    pattern: /generated\s+(plan|walkthrough|capsule|runbook)\s+is\s+proof/i,
    message: "Generated material must not be described as proof."
  },
  {
    code: "skills.agent_user_approval_claim",
    pattern: /agents?\s+may\s+(claim|record)\s+(user approval|user sign-off)/i,
    message: "Agents must not be permitted to claim user approval."
  },
  {
    code: "skills.host_support_claim",
    pattern: /\bhost\s+support\s+is\s+verified\./i,
    message: "Host support must not be claimed without evidence."
  }
];

export function validateSkillAssets(options: { context: ResolvedWorkspaceContext }): SkillAssetValidationResult {
  const root = options.context.workspace_root;
  const diagnostics: Diagnostic[] = [];
  const skills: SkillAssetSummary[] = [];
  const commandReferences: SkillCommandReference[] = [];
  const skillRoot = join(root, ".agents", "skills");

  if (!existsSync(skillRoot)) {
    diagnostics.push(diagnostic("skills.root_missing", "Missing .agents/skills directory.", ".agents/skills"));
  } else {
    const actualSkillNames = readdirSync(skillRoot).sort();
    for (const expected of CANONICAL_SKILLS) {
      if (!actualSkillNames.includes(expected)) {
        diagnostics.push(diagnostic("skills.missing", `Missing canonical skill '${expected}'.`, `.agents/skills/${expected}/SKILL.md`, expected));
      }
    }
  }

  const names = new Set<string>();
  for (const skillName of CANONICAL_SKILLS) {
    const sourcePath = `.agents/skills/${skillName}/SKILL.md`;
    const fullPath = join(root, sourcePath);
    if (!existsSync(fullPath)) {
      continue;
    }
    const source = readFileSync(fullPath, "utf8");
    const frontmatter = parseFrontmatter(source, sourcePath, diagnostics);
    const name = frontmatter?.name ?? "";
    const description = frontmatter?.description ?? "";
    if (name !== skillName) {
      diagnostics.push(diagnostic("skills.name_mismatch", "Skill frontmatter name must match directory name.", sourcePath, name));
    }
    if (!description || description.length < 40) {
      diagnostics.push(diagnostic("skills.description_missing", "Skill description must be specific.", sourcePath, name || skillName));
    }
    if (name && names.has(name)) {
      diagnostics.push(diagnostic("skills.duplicate_name", `Duplicate skill name '${name}'.`, sourcePath, name));
    }
    names.add(name);
    commandReferences.push(...extractCliCommands(source, sourcePath));
    checkForbiddenPatterns(source, sourcePath, diagnostics);
    skills.push({
      name,
      path: sourcePath,
      description,
      complete: diagnostics.every((item) => item.entity_id !== name && item.source_path !== sourcePath)
    });
  }

  const bootstrapPath = "bootstrap/use-cases-plugin.md";
  const bootstrapFullPath = join(root, bootstrapPath);
  const bootstrapSections: string[] = [];
  if (!existsSync(bootstrapFullPath)) {
    diagnostics.push(diagnostic("skills.bootstrap_missing", "Missing use-cases-plugin bootstrap.", bootstrapPath));
  } else {
    const source = readFileSync(bootstrapFullPath, "utf8");
    for (const section of BOOTSTRAP_SECTIONS) {
      if (source.includes(section)) {
        bootstrapSections.push(section);
      } else {
        diagnostics.push(diagnostic("skills.bootstrap_section_missing", `Bootstrap missing '${section}'.`, bootstrapPath));
      }
    }
    for (const phrase of ["repo data", "MCP output", "generated runbooks", "secrets", "private data"]) {
      if (!source.includes(phrase)) {
        diagnostics.push(diagnostic("skills.bootstrap_boundary_missing", `Bootstrap missing '${phrase}'.`, bootstrapPath));
      }
    }
    commandReferences.push(...extractCliCommands(source, bootstrapPath));
    checkForbiddenPatterns(source, bootstrapPath, diagnostics);
  }

  const activationPath = "docs/activation.md";
  const activationFullPath = join(root, activationPath);
  if (!existsSync(activationFullPath)) {
    diagnostics.push(diagnostic("skills.activation_missing", "Missing activation docs.", activationPath));
  } else {
    const source = readFileSync(activationFullPath, "utf8");
    for (const marker of ["Decision Tree", "-> use-cases-plugin", "-> showcase", "-> walkthrough", "-> do not activate"]) {
      if (!source.includes(marker)) {
        diagnostics.push(diagnostic("skills.activation_tree_missing", `Activation docs missing '${marker}'.`, activationPath));
      }
    }
    checkForbiddenPatterns(source, activationPath, diagnostics);
  }

  for (const reference of commandReferences) {
    if (!KNOWN_CLI_COMMANDS.has(reference.command)) {
      diagnostics.push(
        diagnostic("skills.unknown_cli_command", `Unknown CLI command '${reference.command}'.`, reference.source_path, reference.command)
      );
    }
  }

  return {
    schema_version: 1,
    complete: diagnostics.every((item) => item.severity !== "error"),
    skill_count: skills.length,
    skills,
    bootstrap: {
      path: bootstrapPath,
      complete: BOOTSTRAP_SECTIONS.every((section) => bootstrapSections.includes(section)),
      sections: bootstrapSections
    },
    command_references: commandReferences,
    diagnostics
  };
}

function parseFrontmatter(
  source: string,
  sourcePath: string,
  diagnostics: Diagnostic[]
): { name: string; description: string } | null {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    diagnostics.push(diagnostic("skills.frontmatter_missing", "Skill is missing YAML frontmatter.", sourcePath));
    return null;
  }
  const parsed = parseYamlToJson(match[1], sourcePath);
  if (!parsed.ok) {
    diagnostics.push(...parsed.diagnostics);
    return null;
  }
  const value = parsed.value as { name?: unknown; description?: unknown };
  return {
    name: typeof value.name === "string" ? value.name : "",
    description: typeof value.description === "string" ? value.description : ""
  };
}

function extractCliCommands(source: string, sourcePath: string): SkillCommandReference[] {
  const references: SkillCommandReference[] = [];
  for (const match of source.matchAll(/`(?:ucp|pnpm cli --)\s+([^`]+?)`/g)) {
    const tokens = match[1].trim().split(/\s+/);
    if (tokens.length >= 2) {
      references.push({ command: `${tokens[0]} ${tokens[1]}`, source_path: sourcePath });
    }
  }
  return references;
}

function checkForbiddenPatterns(source: string, sourcePath: string, diagnostics: Diagnostic[]): void {
  for (const forbidden of FORBIDDEN_PATTERNS) {
    if (forbidden.pattern.test(source)) {
      diagnostics.push(diagnostic(forbidden.code, forbidden.message, sourcePath));
    }
  }
}

function diagnostic(code: string, message: string, sourcePath: string, entityId: string | null = null): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath.split(sep).join("/"),
    json_pointer: null,
    entity_id: entityId,
    related_ids: []
  };
}
