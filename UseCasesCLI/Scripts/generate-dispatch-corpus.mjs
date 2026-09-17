// Regenerates the CLI dispatch corpus by running every case below through the
// REAL TypeScript CLI, and recording exactly the bytes and exit code it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-dispatch-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/DispatchGoldenCorpus.swift
//     For each case: the argv, the files its sandbox held before the run, the
//     stdout, stderr and exit status of `node packages/cli/dist/index.js`, and
//     the sandbox's `use-cases.yml` afterwards. Covers the row 4a surface:
//     help, version, unknown commands, unknown flags, and the schema, doctor
//     and workflow commands, in both the JSON and the human rendering.
//
// Paths are recorded as placeholders: `$SANDBOX` for the case's sandbox,
// `$CWD` for the directory the CLI ran in, `$REPO` for this repository. The
// Swift test substitutes its own, so the corpus does not depend on where
// either side ran. Non-ASCII output is carried as JSON escapes, so the file
// stays ASCII.
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const cliEntry = join(repositoryRoot, "packages/cli/dist/index.js");
const outputDirectory = join(packageRoot, "Tests/UseCasesCLITests/Entry");

for (const [source, built] of [
  ["packages/cli/src/builtins.ts", "packages/cli/dist/builtins.js"],
  ["packages/cli/src/render.ts", "packages/cli/dist/render.js"],
  ["packages/cli/src/index.ts", "packages/cli/dist/index.js"]
]) {
  if (statSync(join(repositoryRoot, built)).mtimeMs < statSync(join(repositoryRoot, source)).mtimeMs) {
    throw new Error(`${built} is older than ${source}; run pnpm build first`);
  }
}

const CONFIG = (extra = "", dataRoot = ".") => `schema_version: 1
workspace_id: probe
component_id: probe
data_root: ${dataRoot}
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
${extra}`;

const configured = { "use-cases.yml": CONFIG("default_workflow_mode: continuous\n"), "use-cases/.keep": "" };
const S = "$SANDBOX";
const R = "$REPO";

const cases = [
  // help and version
  ["bare", []],
  ["bare_json", ["--json"]],
  ["help_long", ["--help"]],
  ["help_short", ["-h"]],
  ["help_json", ["--help", "--json"]],
  ["help_group", ["matrix", "--help"]],
  ["help_group_json", ["showcase", "-h", "--json"]],
  ["help_leaf", ["matrix", "upsert", "--help"]],
  ["help_leaf_json", ["workflow", "set-mode", "--help", "--json"]],
  ["help_flat_leaf", ["scan", "--help"]],
  ["help_unmatched_tokens_fall_back_to_group", ["doctor", "nothing", "--help"]],
  ["help_unmatched_everything", ["nothing", "at", "all", "--help"]],
  ["help_after_leading_separator", ["--", "--help"]],
  ["version_word", ["version"]],
  ["version_word_json", ["version", "--json"]],
  ["version_long", ["--version"]],
  ["version_short_anywhere", ["scan", "-v", "--json"]],
  ["version_beats_help", ["--help", "--version"]],
  ["version_with_repo", ["version", "--repo", ".", "--json"]],
  // unknown commands
  ["unknown_command", ["frobnicate"]],
  ["unknown_command_json", ["frobnicate", "--json"]],
  ["unknown_group_only", ["matrix"]],
  ["unknown_group_leaf_json", ["matrix", "nope", "--json"]],
  ["unknown_after_leading_separator", ["--", "frobnicate", "--json"]],
  ["unknown_flag_only_is_bare_help", ["--frob"]],
  ["hidden_group_prefix", ["doctor", "--json"]],
  // unknown flags
  ["unknown_flag", ["schema", "list", "--bogus"]],
  ["unknown_flag_json", ["schema", "list", "--bogus", "--json"]],
  ["unknown_flags_plural", ["schema", "list", "--bogus", "-x", "--json"]],
  ["unknown_flag_equals_form", ["doctor", "roots", "--repo=.", "--json"]],
  ["unknown_flag_value_is_skipped", ["doctor", "roots", "--repo", "--bogus", "--json"]],
  ["unknown_flag_after_separator_ignored", ["schema", "list", "--json", "--", "--bogus"]],
  ["unknown_short_digit_is_not_a_flag", ["schema", "list", "-1", "--json"]],
  ["unknown_flag_on_unported_command", ["scan", "--nope", "--json"]],
  // schema
  ["schema_list_json", ["schema", "list", "--json"]],
  ["schema_list_text", ["schema", "list"]],
  ["schema_list_repeated_json", ["schema", "list", "--json", "--json"]],
  ["schema_validate_fixtures_valid", ["schema", "validate-fixtures", "--fixture", `${R}/tests/fixtures/workspaces/minimal-valid`, "--json"]],
  ["schema_validate_fixtures_invalid_json", ["schema", "validate-fixtures", "--fixture", `${R}/tests/fixtures/workspaces/invalid-contracts`, "--json"]],
  ["schema_validate_fixtures_invalid_text", ["schema", "validate-fixtures", "--fixture", `${R}/tests/fixtures/workspaces/invalid-contracts`]],
  ["schema_validate_fixtures_missing_dir", ["schema", "validate-fixtures", "--fixture", `${S}/missing`, "--json"]],
  // doctor roots
  ["doctor_roots_configured", ["doctor", "roots", "--repo", S, "--json"], configured],
  ["doctor_roots_configured_text", ["doctor", "roots", "--repo", S], configured],
  ["doctor_roots_unconfigured", ["doctor", "roots", "--repo", S, "--json"], {}],
  ["doctor_roots_data_root_below", ["doctor", "roots", "--repo", S, "--json"], { "use-cases.yml": CONFIG("", "sub"), "sub/use-cases/.keep": "" }],
  ["doctor_roots_data_root_escapes_config", ["doctor", "roots", "--repo", S, "--json"], { "use-cases.yml": CONFIG("", "../escape") }],
  ["doctor_roots_data_root_escapes_config_text", ["doctor", "roots", "--repo", S], { "use-cases.yml": CONFIG("", "../escape") }],
  ["doctor_roots_missing_repo", ["doctor", "roots", "--repo", `${S}/missing`, "--json"]],
  ["doctor_roots_missing_repo_text", ["doctor", "roots", "--repo", `${S}/missing`]],
  ["doctor_roots_data_root_flag_outside", ["doctor", "roots", "--repo", S, "--data-root", `${S}/..`, "--json"], configured],
  ["doctor_roots_data_root_flag_inside", ["doctor", "roots", "--repo", S, "--data-root", `${S}/inner`, "--json"], { "inner/.keep": "" }],
  ["doctor_roots_data_root_flag_empty", ["doctor", "roots", "--repo", S, "--data-root", "", "--json"], configured],
  ["doctor_roots_component_matches", ["doctor", "roots", "--repo", S, "--component", "probe", "--json"], configured],
  ["doctor_roots_component_unknown", ["doctor", "roots", "--repo", S, "--component", "other", "--json"], configured],
  ["doctor_roots_component_option_unconfigured", ["doctor", "roots", "--repo", S, "--component", "free", "--json"], {}],
  ["doctor_roots_unparseable_config", ["doctor", "roots", "--repo", S, "--json"], { "use-cases.yml": "a: [unclosed\n" }],
  ["doctor_roots_schema_invalid_config", ["doctor", "roots", "--repo", S, "--json"], { "use-cases.yml": "schema_version: 1\n" }],
  ["doctor_roots_repo_is_a_file", ["doctor", "roots", "--repo", `${S}/file.txt`, "--json"], { "file.txt": "x" }],
  // doctor skills
  ["doctor_skills_empty_workspace", ["doctor", "skills", "--repo", S, "--json"], {}],
  ["doctor_skills_empty_skills_directory", ["doctor", "skills", "--repo", S, "--json"], { "skills/.keep": "" }],
  ["doctor_skills_missing_repo", ["doctor", "skills", "--repo", `${S}/missing`, "--json"]],
  // workflow mode
  ["workflow_mode_configured", ["workflow", "mode", "--repo", S, "--json"], configured],
  ["workflow_mode_configured_text", ["workflow", "mode", "--repo", S], configured],
  ["workflow_mode_backfill", ["workflow", "mode", "--repo", S, "--json"], { "use-cases.yml": CONFIG("default_workflow_mode: backfill\n") }],
  ["workflow_mode_absent_key", ["workflow", "mode", "--repo", S, "--json"], { "use-cases.yml": CONFIG() }],
  ["workflow_mode_value_on_next_line", ["workflow", "mode", "--repo", S, "--json"], { "use-cases.yml": CONFIG("default_workflow_mode:\n  audit_only\n") }],
  ["workflow_mode_no_config", ["workflow", "mode", "--repo", S, "--json"], {}],
  ["workflow_mode_no_config_text", ["workflow", "mode", "--repo", S], {}],
  ["workflow_mode_missing_repo", ["workflow", "mode", "--repo", `${S}/missing`, "--json"]],
  // workflow set-mode
  ["workflow_set_mode_changes", ["workflow", "set-mode", "--repo", S, "--mode", "backfill", "--json"], configured],
  ["workflow_set_mode_dashes_canonicalized", ["workflow", "set-mode", "--repo", S, "--mode", "showcase-only", "--json"], configured],
  ["workflow_set_mode_unchanged", ["workflow", "set-mode", "--repo", S, "--mode", "continuous", "--json"], configured],
  ["workflow_set_mode_appends_when_absent", ["workflow", "set-mode", "--repo", S, "--mode", "custom", "--json"], { "use-cases.yml": CONFIG() + "\n\n" }],
  ["workflow_set_mode_quoted_value_left_alone", ["workflow", "set-mode", "--repo", S, "--mode", "custom", "--json"], { "use-cases.yml": CONFIG('default_workflow_mode: "backfill"\n') }],
  ["workflow_set_mode_retired_migration_refused", ["workflow", "set-mode", "--repo", S, "--mode", "migration", "--json"], configured],
  ["workflow_set_mode_missing_mode", ["workflow", "set-mode", "--repo", S, "--json"], configured],
  ["workflow_set_mode_empty_mode", ["workflow", "set-mode", "--repo", S, "--mode", "", "--json"], configured],
  ["workflow_set_mode_text", ["workflow", "set-mode", "--repo", S, "--mode", "audit-only"], configured],
  ["workflow_set_mode_no_config", ["workflow", "set-mode", "--repo", S, "--mode", "backfill", "--json"], {}],
  ["workflow_set_mode_invalid_before_config_read", ["workflow", "set-mode", "--repo", S, "--mode", "nope", "--json"], {}]
];

function escapeNonAscii(text) {
  return text.replace(/[^\x00-\x7f]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

function toPlaceholders(text, sandbox, cwd) {
  return text.split(sandbox).join("$SANDBOX").split(cwd).join("$CWD").split(repositoryRoot).join("$REPO");
}

function fromPlaceholders(text, sandbox, cwd) {
  return text.split("$SANDBOX").join(sandbox).split("$CWD").join(cwd).split("$REPO").join(repositoryRoot);
}

const recorded = [];
for (const [name, args, files = {}] of cases) {
  const sandbox = realpathSync(mkdtempSync(join(tmpdir(), "uc-dispatch-sandbox-")));
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-dispatch-cwd-")));
  try {
    for (const [path, content] of Object.entries(files)) {
      mkdirSync(dirname(join(sandbox, path)), { recursive: true });
      writeFileSync(join(sandbox, path), content);
    }
    const result = spawnSync(process.execPath, [cliEntry, ...args.map((arg) => fromPlaceholders(arg, sandbox, cwd))], {
      cwd,
      encoding: "utf8",
      env: { PATH: process.env.PATH, HOME: process.env.HOME }
    });
    const configPath = join(sandbox, "use-cases.yml");
    recorded.push({
      name,
      args,
      files,
      stdout: toPlaceholders(result.stdout, sandbox, cwd),
      stderr: toPlaceholders(result.stderr, sandbox, cwd),
      status: result.status,
      config_after: existsSync(configPath) ? readFileSync(configPath, "utf8") : null
    });
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
    rmSync(cwd, { recursive: true, force: true });
  }
}

const json = escapeNonAscii(JSON.stringify({ cases: recorded }));
let pounds = "#";
while (json.includes(`"${pounds}`) || json.includes(`\\${pounds}`)) {
  pounds += "#";
}
const names = recorded.map((item) => `    "${item.name}",\n`).join("");
const swift = `// swiftlint:disable line_length single_line_closure_body
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript CLI. DO NOT EDIT BY HAND.
//
// What node packages/cli/dist/index.js wrote and returned for each argv.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-dispatch-corpus.mjs
enum DispatchGoldenCorpus {
  static let caseNames: [String] = [
${names}  ]

  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable line_length single_line_closure_body
`;
mkdirSync(outputDirectory, { recursive: true });
const target = join(outputDirectory, "DispatchGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("DispatchGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
