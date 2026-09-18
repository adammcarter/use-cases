// Regenerates the skill-asset corpus by running every case below through the
// REAL TypeScript, and recording exactly what it returns or throws.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-skills-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCoreTests/Skills/SkillsGoldenCorpus.swift
//     `validateSkillAssets` over real workspaces: this repository's shipped
//     skills, bootstrap, activation docs and Claude manifests, and variations
//     of them -- missing and malformed frontmatter, short descriptions,
//     forbidden claims, CLI references, bootstrap and activation gaps, and
//     plugin and marketplace manifests that do and do not register the skills
//     -- plus the canonical skill and agent lists and the known CLI commands.
//
// The script refuses to run when the dist is older than its src. File contents
// are carried as JSON strings, the corpus is ASCII only, and the use-case
// marker token is escaped, so no text here reads as a marker line.
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const testsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Skills");

for (const name of ["skills/types", "skills/canonicalSkills", "skills/validateSkillAssets", "agents/canonicalAgents", "cli/knownCommands", "roots"]) {
  if (statSync(join(coreRoot, "dist", `${name}.js`)).mtimeMs < statSync(join(coreRoot, "src", `${name}.ts`)).mtimeMs) {
    throw new Error(`dist/${name}.js is older than src; rebuild packages/core first`);
  }
}

const core = await import(join(coreRoot, "dist/index.js"));
const {
  validateSkillAssets,
  resolveWorkspaceContext,
  CANONICAL_SKILLS,
  CANONICAL_AGENTS,
  KNOWN_CLI_COMMANDS,
  KNOWN_FLAT_CLI_COMMANDS,
  BUILTIN_FLAT_CLI_COMMANDS
} = core;

// ---------------------------------------------------------------------------
// Workspaces: the shipped files, with a case's overlay laid over them -- a map
// from path to text, where null deletes the shipped file and
// `{ directory: true }` makes a directory.

const SHIPPED_PATHS = [
  ...CANONICAL_SKILLS.map((skill) => `skills/${skill}/SKILL.md`),
  "bootstrap/use-cases.md",
  "docs/activation.md",
  ".claude-plugin/plugin.json",
  ".claude-plugin/marketplace.json"
];
const shipped = Object.fromEntries(SHIPPED_PATHS.map((path) => [path, readFileSync(join(repositoryRoot, path), "utf8")]));

function frontmatter(name, description, body = "\n# Skill\n") {
  return `---\nname: ${name}\ndescription: ${description}\n---\n${body}`;
}
const LONG = "Use when the reader needs this canonical skill for its real work.";
const skillPath = (skill) => `skills/${skill}/SKILL.md`;
const plugin = (value) => ({ ".claude-plugin/plugin.json": typeof value === "string" ? value : JSON.stringify(value) });
const marketplace = (value) => ({ ".claude-plugin/marketplace.json": typeof value === "string" ? value : JSON.stringify(value) });
const withBody = (body) => ({ [skillPath("init")]: frontmatter("init", LONG, body) });

const cases = [
  { name: "repository_as_shipped", overlay: {} },
  { name: "empty_workspace", overlay: Object.fromEntries(SHIPPED_PATHS.map((path) => [path, null])) },
  { name: "skills_root_missing", overlay: Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])) },
  {
    name: "one_canonical_skill_missing_and_extra_skill_present",
    overlay: { [skillPath("walkthrough")]: null, "skills/walkthrough": { directory: true }, "skills/extra/SKILL.md": frontmatter("extra", LONG) }
  },
  { name: "skill_directory_without_skill_file", overlay: { [skillPath("walkthrough")]: null, "skills/walkthrough/README.md": "nothing" } },
  { name: "frontmatter_missing", overlay: { [skillPath("init")]: "# No frontmatter\n" } },
  { name: "frontmatter_with_crlf_is_missing", overlay: { [skillPath("init")]: `---\r\nname: init\r\ndescription: ${LONG}\r\n---\r\n` } },
  { name: "frontmatter_not_at_start_is_missing", overlay: { [skillPath("init")]: `\n${frontmatter("init", LONG)}` } },
  { name: "frontmatter_without_trailing_newline_is_missing", overlay: { [skillPath("init")]: `---\nname: init\ndescription: ${LONG}\n---` } },
  { name: "frontmatter_yaml_invalid", overlay: { [skillPath("init")]: "---\nname: [init\ndescription: x\n---\nbody\n" } },
  { name: "frontmatter_lazy_match_stops_at_first_fence", overlay: { [skillPath("init")]: `---\nname: init\n---\ndescription: ${LONG}\n---\n` } },
  { name: "frontmatter_name_and_description_not_strings", overlay: { [skillPath("init")]: "---\nname: 42\ndescription: [a, b]\n---\n" } },
  { name: "frontmatter_is_a_list", overlay: { [skillPath("init")]: "---\n- name\n- description\n---\n" } },
  { name: "frontmatter_is_a_scalar", overlay: { [skillPath("init")]: "---\nplain words\n---\n" } },
  { name: "frontmatter_empty_throws", overlay: { [skillPath("init")]: "---\n\n---\n" } },
  { name: "frontmatter_null_document_throws", overlay: { [skillPath("init")]: "---\n~\n---\n" } },
  { name: "name_mismatch", overlay: { [skillPath("init")]: frontmatter("initialise", LONG) } },
  {
    name: "description_length_boundary",
    overlay: {
      [skillPath("init")]: frontmatter("init", "x".repeat(39)),
      [skillPath("showcase")]: frontmatter("showcase", "x".repeat(40)),
      [skillPath("walkthrough")]: frontmatter("walkthrough", `${"x".repeat(38)}\u{1F600}`),
      [skillPath("use-cases")]: frontmatter("use-cases", `${"e\u0301".repeat(20)}`)
    }
  },
  { name: "description_missing", overlay: { [skillPath("init")]: "---\nname: init\n---\n" } },
  {
    name: "duplicate_names_across_skills",
    overlay: { [skillPath("init")]: frontmatter("showcase", LONG), [skillPath("walkthrough")]: frontmatter("showcase", LONG) }
  },
  {
    name: "empty_names_are_not_duplicates",
    overlay: { [skillPath("init")]: "# none\n", [skillPath("walkthrough")]: "# none\n" }
  },
  {
    name: "a_diagnostic_for_one_skill_marks_another_incomplete",
    overlay: { [skillPath("showcase")]: frontmatter("init", LONG) }
  },
  {
    name: "forbidden_patterns",
    overlay: {
      ...withBody("\nThe SHOWCASE   is\nMandatory for everything.\nA required showcase for all work.\n"),
      [skillPath("walkthrough")]: frontmatter("walkthrough", LONG, "\nThe generated capsule is proof.\nGenerated\u00a0runbook is proof.\nAgent may record user sign-off.\nAgents may claim user approval.\n"),
      [skillPath("showcase")]: frontmatter("showcase", LONG, "\nHost support is verified.\nghost support is verified.\n")
    }
  },
  {
    name: "forbidden_patterns_need_ascii_matches",
    overlay: {
      ...withBody("\n\u017fhowcase is mandatory.\nshowcase is\u2028mandatory\nshowcase is\u0085mandatory\nhost support is verified\nagents may record user  approval\n"),
      [skillPath("showcase")]: frontmatter("showcase", LONG, "\nshowcase\u3000is\ufeffmandatory\nhost_support is verified.\n\u212aost\n")
    }
  },
  {
    name: "host_support_claim_needs_an_ascii_word_boundary",
    overlay: {
      ...withBody("\n\u00e9host support is verified.\n"),
      [skillPath("showcase")]: frontmatter("showcase", LONG, "\nghost support is verified.\n_host support is verified.\n9host support is verified.\n")
    }
  },
  {
    name: "cli_command_references",
    overlay: withBody([
      "",
      "`use-cases matrix list` and `use-cases  matrix\tvalidate --repo .` and `pnpm cli -- plan cards`",
      "`use-cases bind --repo .` and `use-cases verify` and `use-cases scan --json` and `use-cases init`",
      "`use-cases foo bar` and `use-cases migrate test-matrix` and `pnpm cli --  showcase start`",
      "`use-cases capsule\nrun --json` and `use-cases\u00a0doctor\u2003skills` and `use-casesmatrix list` and `use-cases` and `use-cases `",
      "`use-cases matrix list`` and ``use-cases schema list` and `pnpm cli matrix list` and `use-cases version x`",
      "`use-cases \ufeffmatrix list` and `use-cases x\u0085y z` and `use-cases approve-run now`",
      "`use-cases  `use-cases matrix remove` and `use-cases \t`pnpm cli -- nope nope` and `use-cases \n\n` done",
      "`use-cases   bind   now  ` and `pnpm cli --matrix list` and `use-cases x y` z` and `use-cases tail only",
      "`use-cases `use-cases single-space now` and `use-cases\t`use-cases single-tab now`",
      ""
    ].join("\n"))
  },
  { name: "skill_file_with_byte_order_mark", overlay: { [skillPath("init")]: `\ufeff${frontmatter("init", LONG)}` } },
  { name: "marketplace_with_byte_order_mark", overlay: marketplace(`\ufeff${shipped[".claude-plugin/marketplace.json"]}`) },
  { name: "marketplace_with_lone_surrogate_escape", overlay: marketplace('{"plugins":[{"name":"use-cases","note":"\\ud800"}]}') },
  { name: "bootstrap_missing", overlay: { "bootstrap/use-cases.md": null } },
  {
    name: "bootstrap_sections_and_boundaries_missing",
    overlay: {
      "bootstrap/use-cases.md": "# Bootstrap\n\n## When to apply\nrepo data and secrets.\n`use-cases nope nope` and `use-cases matrix list`\nshowcase is mandatory\nwhen not to apply\n"
    }
  },
  { name: "activation_missing", overlay: { "docs/activation.md": null } },
  {
    name: "activation_markers_missing_and_forbidden",
    overlay: { "docs/activation.md": "## Decision Tree\n-> use-cases\n->showcase\nhost support is verified.\n`use-cases bogus command`\n" }
  },
  { name: "plugin_manifest_missing", overlay: { ".claude-plugin/plugin.json": null } },
  { name: "plugin_manifest_invalid_json", overlay: plugin("{ nope") },
  { name: "plugin_manifest_is_not_an_object", overlay: plugin("[\"./skills\"]") },
  { name: "plugin_manifest_null", overlay: plugin("null") },
  {
    name: "plugin_manifest_declares_a_skill_directory",
    overlay: {
      ...plugin({ skills: "./custom/" }),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [`custom/${skill}/SKILL.md`, shipped[skillPath(skill)]]))
    }
  },
  {
    name: "plugin_manifest_declares_directories_that_lack_skills",
    overlay: {
      ...plugin({ skills: ["./", 7, "../outside", "/abs", ".//odd//", "custom"] }),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])),
      "custom/init/SKILL.md": shipped[skillPath("init")]
    }
  },
  {
    name: "plugin_manifest_absolute_and_doubled_prefix_paths",
    overlay: {
      ...plugin({ skills: ["/nested", "././nested"] }),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [`nested/${skill}/SKILL.md`, shipped[skillPath(skill)]]))
    }
  },
  {
    name: "plugin_manifest_declares_the_root_as_a_bare_slash",
    overlay: {
      ...plugin({ skills: ["/", "//"] }),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])),
      ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [`${skill}/SKILL.md`, shipped[skillPath(skill)]]))
    }
  },
  { name: "plugin_manifest_with_byte_order_mark", overlay: plugin(`\ufeff${shipped[".claude-plugin/plugin.json"]}`) },
  { name: "marketplace_missing", overlay: { ".claude-plugin/marketplace.json": null } },
  { name: "marketplace_plugins_not_an_array", overlay: marketplace({ plugins: { name: "use-cases" } }) },
  { name: "marketplace_offers_other_plugins", overlay: marketplace({ plugins: [null, 3, "use-cases", { name: "Use-Cases" }, { title: "use-cases" }] }) },
  { name: "marketplace_duplicate_keys_last_wins", overlay: marketplace('{"plugins":[{"name":"use-cases"}],"plugins":[]}') },
  { name: "marketplace_offers_it_among_others", overlay: marketplace({ plugins: [{ name: "other" }, { name: "use-cases", source: "." }] }) },
  { name: "marketplace_invalid_json", overlay: marketplace("{\"plugins\": [") },
  { name: "skills_root_is_a_file_throws", overlay: { ...Object.fromEntries(CANONICAL_SKILLS.map((skill) => [skillPath(skill), null])), skills: "a file" } },
  { name: "skill_file_is_a_directory_throws", overlay: { [skillPath("init")]: null, [`${skillPath("init")}/inner`]: "x" } }
];

function buildWorkspace(overlay) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "use-cases-skills-corpus-")));
  const files = { ...shipped };
  for (const [path, value] of Object.entries(overlay)) {
    if (value === null) {
      delete files[path];
    } else {
      files[path] = value;
    }
  }
  // Files in insertion order: shipped first, then the overlay's additions.
  for (const [path, value] of Object.entries(files)) {
    const target = join(root, path);
    if (typeof value === "object") {
      mkdirSync(target, { recursive: true });
    } else {
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, value);
    }
  }
  return root;
}

function runCase(testCase) {
  const root = buildWorkspace(testCase.overlay);
  try {
    const context = resolveWorkspaceContext({ workspaceRoot: root });
    let outcome;
    try {
      outcome = { result: validateSkillAssets({ context }) };
    } catch (error) {
      outcome = { thrown: { code: error.code ?? null, message: error.message } };
    }
    const text = JSON.stringify(outcome).split(root).join("<workspace>");
    return { name: testCase.name, overlay: testCase.overlay, outcome: JSON.parse(text) };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const corpus = {
  shipped,
  canonical_skills: [...CANONICAL_SKILLS],
  canonical_agents: [...CANONICAL_AGENTS],
  known_cli_commands: [...KNOWN_CLI_COMMANDS],
  known_flat_cli_commands: [...KNOWN_FLAT_CLI_COMMANDS],
  builtin_flat_cli_commands: [...BUILTIN_FLAT_CLI_COMMANDS],
  cases: cases.map(runCase)
};

// ---------------------------------------------------------------------------
// Output

function asciiJson(value) {
  return JSON.stringify(value)
    .replace(/[\u007f-\uffff]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`)
    .replaceAll("@use-case", "\\u0040use-case");
}

const json = asciiJson(corpus);
let pounds = "#";
while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
  pounds += "#";
}
const disabledRules = "line_length single_line_closure_body";
const contents = `// swiftlint:disable ${disabledRules}
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript skill-asset code. DO NOT EDIT BY HAND.
//
// What packages/core/dist/skills' validateSkillAssets returned or threw for each
// workspace, and the canonical skill, agent and CLI command lists.
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-skills-corpus.mjs
enum SkillsGoldenCorpus {
  static let caseNames: [String] = [
${corpus.cases.map((item) => `    ${asciiJson(item.name)},`).join("\n")}
  ]

  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable ${disabledRules}
`;
mkdirSync(testsDirectory, { recursive: true });
const target = join(testsDirectory, "SkillsGoldenCorpus.swift");
writeFileSync(target, contents);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("corpus is not ASCII");
}
console.log(`wrote ${target}: ${corpus.cases.length} cases`);
