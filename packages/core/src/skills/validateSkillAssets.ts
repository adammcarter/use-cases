import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { isPathContained, type ResolvedWorkspaceContext } from "../roots.js";
import { diagnostic, parseYamlToJson, type Diagnostic } from "../schema/index.js";
import type {
  SkillAssetSummary,
  SkillAssetValidationResult,
  SkillCommandReference,
  SkillHostRegistrationResult,
  SkillHostRegistrationSummary
} from "./types.js";
import { CANONICAL_SKILLS } from "./canonicalSkills.js";

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
// Flat, single-segment commands (no subcommand) shipped by the marker / keyless
// tier. A reference like `uc bind --repo ...` has a flag as its second token, so
// it is validated by its bare command name, not a `command subcommand` pair.
const KNOWN_FLAT_CLI_COMMANDS = new Set([
  "init",
  "bind",
  "scan",
  "verify",
  "recover",
  "keygen",
  "prove",
  "validate-ledger"
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

  const bootstrapPath = "bootstrap/use-cases.md";
  const bootstrapFullPath = join(root, bootstrapPath);
  const bootstrapSections: string[] = [];
  if (!existsSync(bootstrapFullPath)) {
    diagnostics.push(diagnostic("skills.bootstrap_missing", "Missing use-cases bootstrap.", bootstrapPath));
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
    for (const marker of ["Decision Tree", "-> use-cases", "-> showcase", "-> walkthrough", "-> migration", "-> do not activate"]) {
      if (!source.includes(marker)) {
        diagnostics.push(diagnostic("skills.activation_tree_missing", `Activation docs missing '${marker}'.`, activationPath));
      }
    }
    checkForbiddenPatterns(source, activationPath, diagnostics);
  }

  for (const reference of commandReferences) {
    const bare = reference.command.split(/\s+/)[0];
    const known = KNOWN_CLI_COMMANDS.has(reference.command) || KNOWN_FLAT_CLI_COMMANDS.has(bare);
    if (!known) {
      diagnostics.push(
        diagnostic("skills.unknown_cli_command", `Unknown CLI command '${reference.command}'.`, reference.source_path, reference.command)
      );
    }
  }

  const hostRegistration = validateHostRegistration(root, diagnostics);

  return {
    schema_version: 1,
    complete: diagnostics.every((item) => item.severity !== "error"),
    skill_count: skills.length,
    skills,
    host_registration: hostRegistration,
    bootstrap: {
      path: bootstrapPath,
      complete: BOOTSTRAP_SECTIONS.every((section) => bootstrapSections.includes(section)),
      sections: bootstrapSections
    },
    command_references: commandReferences,
    diagnostics
  };
}

const CLAUDE_MANIFEST_PATH = ".claude-plugin/plugin.json";
const CLAUDE_MARKETPLACE_PATH = ".claude-plugin/marketplace.json";
const PLUGIN_NAME = "use-cases";
// Claude always scans `skills/` at plugin root on top of anything the manifest
// declares, so it is part of the candidate set even when unlisted.
const IMPLICIT_SKILL_ROOTS = ["./skills"];

// Asset validation answers "do the SKILL.md files exist and read correctly?".
// This answers the question that actually matters to an agent: "can the host
// reach them?" Both must hold, and only the first one used to be checked.
//: @use-case:skills.assets.unreachable_skills_fail_doctor
function validateHostRegistration(root: string, diagnostics: Diagnostic[]): SkillHostRegistrationResult {
  const hosts: SkillHostRegistrationSummary[] = [];
  const manifestFullPath = join(root, CLAUDE_MANIFEST_PATH);

  if (!existsSync(manifestFullPath)) {
    diagnostics.push(diagnostic("skills.host_manifest_missing", "Missing Claude plugin manifest.", CLAUDE_MANIFEST_PATH));
    return { complete: false, hosts };
  }

  const declaresSkillRoot = declaredSkillRoots(root, manifestFullPath).some((candidate) =>
    // A declared path only counts when the canonical skills are genuinely
    // beneath it. A manifest can point anywhere; the host will not find skills
    // that are not there.
    CANONICAL_SKILLS.every((skill) => existsSync(join(root, candidate, skill, "SKILL.md")))
  );
  if (!declaresSkillRoot) {
    diagnostics.push(
      diagnostic(
        "skills.host_not_declared",
        "Claude plugin manifest does not declare a directory containing the canonical skills.",
        CLAUDE_MANIFEST_PATH
      )
    );
  }

  const installable = marketplaceListsPlugin(join(root, CLAUDE_MARKETPLACE_PATH));
  if (!installable) {
    diagnostics.push(
      diagnostic(
        "skills.host_not_installable",
        `Marketplace manifest does not offer '${PLUGIN_NAME}', so the plugin manifest is never read.`,
        CLAUDE_MARKETPLACE_PATH
      )
    );
  }

  hosts.push({ host: "claude", manifest_path: CLAUDE_MANIFEST_PATH, declares_skill_root: declaresSkillRoot, installable });
  return { complete: declaresSkillRoot && installable, hosts };
}
//: @use-case:end skills.assets.unreachable_skills_fail_doctor

function declaredSkillRoots(root: string, manifestFullPath: string): string[] {
  const manifest = readJsonOrNull(manifestFullPath) as { skills?: unknown } | null;
  const declared = manifest?.skills;
  const entries = typeof declared === "string" ? [declared] : Array.isArray(declared) ? declared : [];
  const paths = [...entries.filter((entry): entry is string => typeof entry === "string"), ...IMPLICIT_SKILL_ROOTS];
  return paths.map((entry) => entry.replace(/^\.\//, "").replace(/\/+$/, "")).filter((entry) => entry.length > 0 && isPathContained(root, join(root, entry)));
}

function marketplaceListsPlugin(marketplaceFullPath: string): boolean {
  const marketplace = readJsonOrNull(marketplaceFullPath) as { plugins?: unknown } | null;
  if (!Array.isArray(marketplace?.plugins)) {
    return false;
  }
  return marketplace.plugins.some((plugin) => (plugin as { name?: unknown } | null)?.name === PLUGIN_NAME);
}

function readJsonOrNull(path: string): unknown {
  if (!existsSync(path)) {
    return null;
  }
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
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
  for (const match of source.matchAll(/`(?:uc|pnpm cli --)\s+([^`]+?)`/g)) {
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

