// Regenerates the CLI matrix and init corpus by running every case below
// through the REAL TypeScript CLI, and recording exactly the bytes, exit code
// and files it produced.
//
//   pnpm build
//   node UseCasesCLI/Scripts/generate-matrix-init-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCLITests/Entry/MatrixInitGoldenCorpus.swift
//     For each case: the argv, how its sandbox was set up (files, directories,
//     symlinks, a git repository and its core.hooksPath), the stdout, stderr
//     and exit status of `node packages/cli/dist/index.js`, every file,
//     directory and symlink the sandbox holds afterwards (file modes and
//     contents included, `.git` left out), and the core.hooksPath git reports
//     afterwards. Covers row 4b: `init` and `matrix validate|list|status|
//     upsert|remove`, golden, bad and edge, in the JSON and human renderings.
//
// A sandbox is a temporary directory holding `demo-repo` (the workspace, whose
// name init derives the component from) and `outside`. Paths are recorded as
// placeholders: `$ROOT` for the temporary directory, `$SANDBOX` for
// `$ROOT/demo-repo`, `$CWD` for the directory the CLI ran in, `$REPO` for this
// repository, and `$TODAY` for the UTC day init dated AGENTS.md with.
//
// git runs with global and system configuration switched off, so a user's own
// core.hooksPath cannot leak into the corpus. File contents are carried as
// JSON strings and the corpus is ASCII only, so the marker text inside init's
// js-vitest example never appears as a line of its own in this repository.
import { spawnSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
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
  ["packages/cli/src/commands/matrix.ts", "packages/cli/dist/commands/matrix.js"],
  ["packages/cli/src/runtime.ts", "packages/cli/dist/runtime.js"],
  ["packages/cli/src/render.ts", "packages/cli/dist/render.js"],
  ["packages/core/src/useCases/mutateUseCaseMatrix.ts", "packages/core/dist/useCases/mutateUseCaseMatrix.js"],
  ["packages/core/src/init/scaffold.ts", "packages/core/dist/init/scaffold.js"]
]) {
  if (statSync(join(repositoryRoot, built)).mtimeMs < statSync(join(repositoryRoot, source)).mtimeMs) {
    throw new Error(`${built} is older than ${source}; run pnpm build first`);
  }
}

const { computeSemanticHash, parseYamlToJson } = await import(join(repositoryRoot, "packages/core/dist/index.js"));

const GIT_ISOLATION = { GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
const ENVIRONMENT = { PATH: process.env.PATH, HOME: process.env.HOME, ...GIT_ISOLATION };

// ---------------------------------------------------------------------------
// Workspace fixtures
// ---------------------------------------------------------------------------

const CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

function row(id, fields = {}) {
  const {
    title = "Row",
    lifecycle = "active",
    value = "core",
    journey = "golden",
    tags = null,
    hosts = [["codex.cli", true]],
    sourceRefs = null,
    extra = ""
  } = fields;
  const lines = [
    `  - id: ${id}`,
    `    title: ${title}`,
    `    lifecycle: ${lifecycle}`,
    `    value_tier: ${value}`,
    `    journey_role: ${journey}`,
    "    usage_frequency: common"
  ];
  if (tags) lines.push(`    tags: [${tags.join(", ")}]`);
  if (sourceRefs) {
    lines.push("    source_refs:");
    for (const path of sourceRefs) lines.push("      - kind: file", `        path: ${path}`);
  }
  lines.push(
    "    actor: agent",
    "    intent: Exist.",
    "    preconditions: [Nothing.]",
    "    trigger: Nothing.",
    "    scenarios:",
    `      - id: ${id}.golden_runs`,
    "        kind: steps",
    "        steps: [Run it.]",
    "        observable_outcomes: [It passes.]",
    "    observable_outcomes: [It exists.]"
  );
  if (hosts.length > 0) {
    lines.push("    host_applicability:");
    for (const [surface, supported] of hosts) {
      lines.push(`      - host_surface: ${surface}`, `        supported: ${supported}`);
    }
  }
  lines.push("    verification_policy:", "      mode: none", "    approval_policy:", "      mode: none");
  if (extra) lines.push(extra);
  return lines.join("\n");
}

function shard(featureId, rows) {
  return `schema_version: 1
# a comment the mutation does not keep
feature:
  id: ${featureId}
  name: Probe
  summary: Probe.
use_cases:
${rows.join("\n")}
`;
}

const SEED = shard("probe.core", [row("probe.core.seed", { title: "Seed row", tags: ["seed"] })]);
const seedRow = parseYamlToJson(SEED, "seed.yml").value.use_cases[0];
const SEED_HASH = computeSemanticHash(seedRow);
const STALE_HASH = "sha256:0000000000000000000000000000000000000000000000000000000000000000";

const seeded = { files: { "demo-repo/use-cases.yml": CONFIG, "demo-repo/use-cases/probe.yml": SEED } };

const INVENTORY = {
  files: {
    "demo-repo/use-cases.yml": CONFIG,
    "demo-repo/use-cases/alpha.yml": shard("probe.alpha", [
      row("probe.alpha.one", { value: "critical", journey: "golden", tags: ["product", "fast"], sourceRefs: ["src/one.ts"] }),
      row("probe.alpha.two", { value: "supporting", journey: "edge", lifecycle: "planned", tags: ["primitive"], hosts: [["claude.cli", true], ["codex.cli", false]] })
    ]),
    "demo-repo/use-cases/nested/beta.yml": shard("probe.beta", [
      row("probe.beta.three", { value: "core", journey: "alternate", lifecycle: "deprecated", tags: ["fast"], hosts: [], sourceRefs: ["./src/three.ts", "src\\win.ts"] }),
      row("probe.beta.four", { value: "long_tail", journey: "edge", tags: ["product"] })
    ]),
    "demo-repo/use-cases/notes.txt": "not a use-case file\n"
  }
};

const BROKEN = "schema_version: 1\nfeature:\n  id: probe.core\n";
const damaged = {
  files: { ...seeded.files, "demo-repo/use-cases/broken.yml": BROKEN }
};
const duplicated = {
  files: {
    ...seeded.files,
    "demo-repo/use-cases/copy.yml": shard("probe.copy", [row("probe.core.seed", { title: "Copy" })])
  }
};
const unconfiguredSeed = { files: { "demo-repo/use-cases/probe.yml": SEED } };

const NEW_ROW = {
  id: "probe.core.alpha",
  title: "Alpha",
  lifecycle: "planned",
  value_tier: "core",
  journey_role: "golden",
  usage_frequency: "common"
};
const NEW_JSON = JSON.stringify(NEW_ROW);
const SEED_RETITLED = JSON.stringify({ ...seedRow, title: "Seed retitled" });

const S = "$SANDBOX";

// ---------------------------------------------------------------------------
// Cases: [name, args, setup]
// ---------------------------------------------------------------------------

const matrixValidate = [
  ["validate_clean_json", ["matrix", "validate", "--repo", S, "--json"], seeded],
  ["validate_clean_text", ["matrix", "validate", "--repo", S], seeded],
  ["validate_inventory_json", ["matrix", "validate", "--repo", S, "--json"], INVENTORY],
  ["validate_no_use_cases_directory", ["matrix", "validate", "--repo", S, "--json"], { files: { "demo-repo/use-cases.yml": CONFIG } }],
  ["validate_unconfigured_workspace", ["matrix", "validate", "--repo", S, "--json"], unconfiguredSeed],
  ["validate_damaged_is_incomplete_json", ["matrix", "validate", "--repo", S, "--json"], damaged],
  ["validate_damaged_is_incomplete_text", ["matrix", "validate", "--repo", S], damaged],
  ["validate_duplicate_ids", ["matrix", "validate", "--repo", S, "--json"], duplicated],
  ["validate_duplicate_ids_text", ["matrix", "validate", "--repo", S], duplicated],
  ["validate_unparseable_yaml", ["matrix", "validate", "--repo", S, "--json"], { files: { ...seeded.files, "demo-repo/use-cases/bad.yaml": "a: [unclosed\n" } }],
  ["validate_symlink_rejected", ["matrix", "validate", "--repo", S, "--json"], { ...seeded, symlinks: [["demo-repo/use-cases/link.yml", "probe.yml"]] }],
  ["validate_missing_repo_json", ["matrix", "validate", "--repo", `${S}/missing`, "--json"]],
  ["validate_missing_repo_text", ["matrix", "validate", "--repo", `${S}/missing`]],
  ["validate_data_root_escape", ["matrix", "validate", "--repo", S, "--data-root", "$ROOT/outside", "--json"], seeded],
  ["validate_data_root_inside", ["matrix", "validate", "--repo", S, "--data-root", `${S}/inner`, "--json"], { files: { "demo-repo/inner/use-cases/probe.yml": SEED } }],
  ["validate_component_unknown", ["matrix", "validate", "--repo", S, "--component", "other", "--json"], seeded],
  ["validate_unparseable_config", ["matrix", "validate", "--repo", S, "--json"], { files: { "demo-repo/use-cases.yml": "a: [unclosed\n" } }],
  ["validate_unparseable_config_text", ["matrix", "validate", "--repo", S], { files: { "demo-repo/use-cases.yml": "a: [unclosed\n" } }]
];

const matrixList = [
  ["list_all_json", ["matrix", "list", "--repo", S, "--json"], INVENTORY],
  ["list_all_text", ["matrix", "list", "--repo", S], INVENTORY],
  ["list_by_value", ["matrix", "list", "--repo", S, "--value", "critical", "--json"], INVENTORY],
  ["list_by_repeated_value", ["matrix", "list", "--repo", S, "--value", "critical", "--value", "long_tail", "--json"], INVENTORY],
  ["list_by_journey_role", ["matrix", "list", "--repo", S, "--journey-role", "edge", "--json"], INVENTORY],
  ["list_by_lifecycle", ["matrix", "list", "--repo", S, "--lifecycle", "deprecated", "--json"], INVENTORY],
  ["list_by_host", ["matrix", "list", "--repo", S, "--host", "codex.cli", "--json"], INVENTORY],
  ["list_by_tag_any", ["matrix", "list", "--repo", S, "--tag", "primitive", "--tag", "fast", "--json"], INVENTORY],
  ["list_by_changed_path", ["matrix", "list", "--repo", S, "--changed-path", "src/three.ts", "--json"], INVENTORY],
  ["list_by_changed_path_backslash", ["matrix", "list", "--repo", S, "--changed-path", "./src/win.ts", "--json"], INVENTORY],
  ["list_filters_combine", ["matrix", "list", "--repo", S, "--tag", "fast", "--value", "core", "--json"], INVENTORY],
  ["list_unknown_value_matches_nothing", ["matrix", "list", "--repo", S, "--value", "nope", "--json"], INVENTORY],
  ["list_empty_tag_is_no_filter", ["matrix", "list", "--repo", S, "--tag", "", "--json"], INVENTORY],
  ["list_flag_value_missing_at_end", ["matrix", "list", "--repo", S, "--json", "--value"], INVENTORY],
  ["list_strict_complete", ["matrix", "list", "--repo", S, "--strict", "--json"], seeded],
  ["list_strict_incomplete_json", ["matrix", "list", "--repo", S, "--strict", "--json"], damaged],
  ["list_strict_incomplete_text", ["matrix", "list", "--repo", S, "--strict"], damaged],
  ["list_incomplete_not_strict", ["matrix", "list", "--repo", S, "--json"], damaged],
  ["list_empty_workspace_text", ["matrix", "list", "--repo", S], { files: { "demo-repo/use-cases.yml": CONFIG } }],
  ["list_missing_repo", ["matrix", "list", "--repo", `${S}/missing`, "--json"]],
  ["list_unknown_flag", ["matrix", "list", "--repo", S, "--values", "core", "--json"], INVENTORY]
];

const matrixStatus = [
  ["status_clean_json", ["matrix", "status", "--repo", S, "--json"], seeded],
  ["status_clean_text", ["matrix", "status", "--repo", S], seeded],
  ["status_incomplete_matrix_json", ["matrix", "status", "--repo", S, "--json"], damaged],
  ["status_incomplete_matrix_text", ["matrix", "status", "--repo", S], damaged],
  ["status_damaged_evidence", ["matrix", "status", "--repo", S, "--json"], { files: { ...seeded.files, "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "not json\n" } }],
  ["status_damaged_evidence_text", ["matrix", "status", "--repo", S], { files: { ...seeded.files, "demo-repo/evidence/by-id/ev/evidence.bad.jsonl": "{\"schema_version\":1}\n" } }],
  ["status_missing_repo", ["matrix", "status", "--repo", `${S}/missing`, "--json"]]
];

const upsert = (rest, setup = seeded) => [["matrix", "upsert", "--repo", S, ...rest], setup];
const matrixUpsert = [
  ["upsert_creates_json", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_creates_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON])],
  ["upsert_updates_existing", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", SEED_RETITLED, "--json"])],
  ["upsert_updates_with_matching_hash", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", SEED_RETITLED, "--expected-hash", SEED_HASH, "--json"])],
  ["upsert_stale_hash_blocks_json", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", SEED_RETITLED, "--expected-hash", STALE_HASH, "--json"])],
  ["upsert_stale_hash_blocks_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", SEED_RETITLED, "--expected-hash", STALE_HASH])],
  ["upsert_stale_hash_ignored_on_create", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--expected-hash", STALE_HASH, "--json"])],
  ["upsert_empty_hash_ignored", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", SEED_RETITLED, "--expected-hash", "", "--json"])],
  ["upsert_new_file", ...upsert(["--file", "use-cases/new/fresh.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_path_escape_json", ...upsert(["--file", "../outside/escape.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_path_escape_text", ...upsert(["--file", "../outside/escape.yml", "--use-case-json", NEW_JSON])],
  ["upsert_absolute_path_escape", ...upsert(["--file", "$ROOT/outside/escape.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_outside_use_cases_directory", ...upsert(["--file", "other/probe.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_not_a_yaml_file", ...upsert(["--file", "use-cases/probe.json", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_incomplete_matrix_blocks", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--json"], damaged)],
  ["upsert_schema_invalid_row_blocks", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", JSON.stringify({ id: "probe.core.bad", title: 7 }), "--json"])],
  ["upsert_schema_invalid_row_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", JSON.stringify({ id: "probe.core.bad" })])],
  ["upsert_index_keys_are_reordered", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '{"zeta":1,"id":"probe.core.bad","10":true,"2":false,"title":"T"}', "--json"])],
  ["upsert_duplicate_key_last_wins", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '{"title":"First","id":"probe.core.alpha","lifecycle":"planned","value_tier":"core","journey_role":"golden","usage_frequency":"common","title":"Second"}', "--json"])],
  ["upsert_unicode_row", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", JSON.stringify({ ...NEW_ROW, title: "Café — 🚀 \"quoted\": yes" }), "--json"])],
  ["upsert_missing_id", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '{"title":"No id"}', "--json"])],
  ["upsert_non_string_id", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '{"id":5}', "--json"])],
  ["upsert_empty_string_id", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '{"id":""}', "--json"])],
  ["upsert_json_null", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "null", "--json"])],
  ["upsert_json_zero", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "0", "--json"])],
  ["upsert_json_number", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "12", "--json"])],
  ["upsert_json_array", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "[1,2]", "--json"])],
  ["upsert_json_string", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", '"probe.core.alpha"', "--json"])],
  ["upsert_invalid_json_json", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "{not json", "--json"])],
  ["upsert_invalid_json_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "{\"id\": nope}"])],
  ["upsert_invalid_json_empty_object_trailer", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "{} x", "--json"])],
  ["upsert_both_inputs", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--use-case-file", "$ROOT/row.json", "--json"])],
  ["upsert_both_inputs_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--use-case-file", "$ROOT/row.json"])],
  ["upsert_no_input", ...upsert(["--file", "use-cases/probe.yml", "--json"])],
  ["upsert_no_file", ...upsert(["--use-case-json", NEW_JSON, "--json"])],
  ["upsert_empty_file_flag", ...upsert(["--file", "", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_empty_inline_json", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", "", "--json"])],
  ["upsert_empty_input_file_flag_with_inline", ...upsert(["--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--use-case-file", "", "--json"])],
  ["upsert_file_flag_swallows_next_flag", ...upsert(["--file", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_from_file", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "$ROOT/row.json", "--json"], { files: { ...seeded.files, "row.json": NEW_JSON + "\n" } })],
  ["upsert_from_file_with_bom", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "$ROOT/row.json", "--json"], { files: { ...seeded.files, "row.json": "﻿" + NEW_JSON } })],
  ["upsert_from_missing_file_json", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "$ROOT/missing.json", "--json"])],
  ["upsert_from_missing_file_text", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "$ROOT/missing.json"])],
  ["upsert_from_relative_missing_file", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "nowhere/row.json", "--json"])],
  ["upsert_from_directory", ...upsert(["--file", "use-cases/probe.yml", "--use-case-file", "$ROOT/outside", "--json"])],
  ["upsert_missing_repo", ["matrix", "upsert", "--repo", `${S}/missing`, "--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--json"]],
  ["upsert_missing_repo_before_arguments", ["matrix", "upsert", "--repo", `${S}/missing`, "--json"]],
  ["upsert_data_root_escape", ...upsert(["--data-root", "$ROOT", "--file", "use-cases/probe.yml", "--use-case-json", NEW_JSON, "--json"])],
  ["upsert_another_commands_flag_is_known", ...upsert(["--file", "use-cases/probe.yml", "--use-case", NEW_JSON, "--json"])]
];

const remove = (rest, setup = seeded) => [["matrix", "remove", "--repo", S, ...rest], setup];
const withRemoval = {
  files: {
    "demo-repo/use-cases.yml": CONFIG,
    "demo-repo/use-cases/probe.yml": shard("probe.core", [
      row("probe.core.seed", {
        extra: "    extensions:\n      use-cases/removal:\n        note: kept\n        reason: old\n      zeta/other: 1"
      })
    ])
  }
};
const matrixRemove = [
  ["remove_json", ...remove(["--use-case", "probe.core.seed", "--reason", "retired", "--json"])],
  ["remove_text", ...remove(["--use-case", "probe.core.seed", "--reason", "retired"])],
  ["remove_with_matching_hash", ...remove(["--use-case", "probe.core.seed", "--reason", "retired", "--expected-hash", SEED_HASH, "--json"])],
  ["remove_stale_hash", ...remove(["--use-case", "probe.core.seed", "--reason", "retired", "--expected-hash", STALE_HASH, "--json"])],
  ["remove_keeps_existing_extensions", ...remove(["--use-case", "probe.core.seed", "--reason", "retired again", "--json"], withRemoval)],
  ["remove_unknown_row_json", ...remove(["--use-case", "probe.core.nope", "--reason", "retired", "--json"])],
  ["remove_unknown_row_text", ...remove(["--use-case", "probe.core.nope", "--reason", "retired"])],
  ["remove_ambiguous_row", ...remove(["--use-case", "probe.core.seed", "--reason", "retired", "--json"], duplicated)],
  ["remove_incomplete_matrix", ...remove(["--use-case", "probe.core.seed", "--reason", "retired", "--json"], damaged)],
  ["remove_missing_reason", ...remove(["--use-case", "probe.core.seed", "--json"])],
  ["remove_empty_reason", ...remove(["--use-case", "probe.core.seed", "--reason", "", "--json"])],
  ["remove_empty_use_case_text", ...remove(["--use-case", "", "--reason", "retired"])],
  ["remove_missing_repo", ["matrix", "remove", "--repo", `${S}/missing`, "--use-case", "probe.core.seed", "--reason", "x", "--json"]],
  ["remove_another_commands_flag_is_accepted", ...remove(["--use-case", "probe.core.seed", "--reason", "x", "--file", "use-cases/probe.yml", "--json"])]
];

const init = (rest, setup = {}) => [["init", "--repo", S, ...rest], setup];
const existingConfig = { files: { "demo-repo/use-cases.yml": "schema_version: 1\n" } };
const initCases = [
  ["init_generic_json", ...init(["--json"])],
  ["init_generic_text", ...init([])],
  ["init_js_vitest_json", ...init(["--template", "js-vitest", "--json"], { files: { "demo-repo/pnpm-lock.yaml": "lockfileVersion: '9.0'\n" } })],
  ["init_python_pytest_text", ...init(["--template", "python-pytest"])],
  ["init_go_test_json", ...init(["--template", "go-test", "--json"])],
  ["init_unknown_template_json", ...init(["--template", "js-jest", "--json"])],
  ["init_unknown_template_text", ...init(["--template", "js-jest"])],
  ["init_empty_template", ...init(["--template", "", "--json"])],
  ["init_template_without_value", ...init(["--json", "--template"])],
  ["init_component_flag", ...init(["--component", "My App.Web!", "--json"])],
  ["init_component_derives_to_workspace", ...init(["--component", "---", "--json"])],
  ["init_existing_config_json", ...init(["--json"], existingConfig)],
  ["init_existing_config_text", ...init([], existingConfig)],
  ["init_force_overwrites", ...init(["--force", "--json"], existingConfig)],
  ["init_force_after_separator", ["init", "--repo", S, "--json", "--", "--force"], existingConfig],
  ["init_git_repository_json", ...init(["--json"], { git: true })],
  ["init_git_repository_text", ...init([], { git: true })],
  ["init_git_local_hooks_path", ...init(["--json"], { git: true, hooksPath: "tools/hooks" })],
  ["init_git_hooks_path_escapes_json", ...init(["--json"], { git: true, hooksPath: "../outside/hooks" })],
  ["init_git_hooks_path_escapes_text", ...init([], { git: true, hooksPath: "../outside/hooks" })],
  ["init_path_escape_json", ...init(["--json"], { directories: ["outside"], symlinks: [["demo-repo/use-cases", "../outside"]] })],
  ["init_path_escape_text", ...init([], { directories: ["outside"], symlinks: [["demo-repo/use-cases", "../outside"]] })],
  ["init_existing_agents_and_hooks", ...init(["--json"], {
    files: {
      "demo-repo/AGENTS.md": "# Agents\n\nUse-case driven development for this repo? no\n",
      "demo-repo/.gitignore": "node_modules\n",
      "demo-repo/.githooks/pre-commit": "#!/bin/sh\necho mine"
    }
  })],
  ["init_creates_missing_repository", ...init(["--json"], { noRepository: true })],
  ["init_repository_is_a_file_json", ["init", "--repo", "$ROOT/file.txt", "--json"], { noRepository: true, files: { "file.txt": "x" } }],
  ["init_repository_is_a_file_text", ["init", "--repo", "$ROOT/file.txt"], { noRepository: true, files: { "file.txt": "x" } }],
  ["init_unknown_flag_is_ignored", ...init(["--bogus", "--json"])],
  ["init_after_leading_separator", ["--", "init", "--repo", S, "--json"]]
];

const cases = [...matrixValidate, ...matrixList, ...matrixStatus, ...matrixUpsert, ...matrixRemove, ...initCases];

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

function escapeNonAscii(text) {
  return text.replace(/[^\x00-\x7f]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`);
}

function git(args, cwd) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", env: ENVIRONMENT });
  if (result.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${result.stderr}`);
  return result;
}

function tree(root) {
  const entries = [];
  const walk = (relative) => {
    const absolute = relative ? join(root, relative) : root;
    for (const name of readdirSync(absolute)) {
      if (name === ".git") continue;
      const path = relative ? `${relative}/${name}` : name;
      const full = join(root, path);
      const stat = lstatSync(full);
      if (stat.isSymbolicLink()) {
        entries.push({ path, kind: "symlink", target: readlinkSync(full) });
      } else if (stat.isDirectory()) {
        entries.push({ path, kind: "directory" });
        walk(path);
      } else {
        entries.push({ path, kind: "file", mode: (stat.mode & 0o777).toString(8), content: readFileSync(full, "utf8") });
      }
    }
  };
  walk("");
  return entries.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
}

const today = new Date().toISOString().slice(0, 10);
const recorded = [];
for (const [name, args, setup = {}] of cases) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "uc-matrix-init-")));
  const sandbox = join(root, "demo-repo");
  const cwd = realpathSync(mkdtempSync(join(tmpdir(), "uc-matrix-init-cwd-")));
  const placeholders = (text) =>
    text.split(sandbox).join("$SANDBOX").split(root).join("$ROOT").split(cwd).join("$CWD").split(repositoryRoot).join("$REPO");
  const concrete = (text) =>
    text.split("$SANDBOX").join(sandbox).split("$ROOT").join(root).split("$CWD").join(cwd).split("$REPO").join(repositoryRoot);
  try {
    mkdirSync(join(root, "outside"));
    if (!setup.noRepository) mkdirSync(sandbox);
    if (setup.git) git(["init", "-q"], sandbox);
    if (setup.hooksPath) git(["config", "core.hooksPath", setup.hooksPath], sandbox);
    for (const directory of setup.directories ?? []) mkdirSync(join(root, directory), { recursive: true });
    for (const [path, content] of Object.entries(setup.files ?? {})) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    }
    for (const [path, target] of setup.symlinks ?? []) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      symlinkSync(target, join(root, path));
    }
    const result = spawnSync(process.execPath, [cliEntry, ...args.map(concrete)], { cwd, encoding: "utf8", env: ENVIRONMENT });
    const hooks = existsSync(join(sandbox, ".git"))
      ? spawnSync("git", ["config", "--get", "core.hooksPath"], { cwd: sandbox, encoding: "utf8", env: ENVIRONMENT })
      : null;
    const after = tree(root).map((entry) =>
      entry.kind === "file" ? { ...entry, content: placeholders(entry.content.split(today).join("$TODAY")) } : entry
    );
    recorded.push({
      name,
      args,
      setup: {
        git: Boolean(setup.git),
        hooks_path: setup.hooksPath ?? null,
        repository: !setup.noRepository,
        directories: setup.directories ?? [],
        files: Object.entries(setup.files ?? {}).map(([path, content]) => ({ path, content })),
        symlinks: (setup.symlinks ?? []).map(([path, target]) => ({ path, target }))
      },
      stdout: placeholders(result.stdout),
      stderr: placeholders(result.stderr),
      status: result.status,
      tree_after: after,
      hooks_path_after: hooks && hooks.status === 0 ? hooks.stdout : null
    });
  } finally {
    rmSync(root, { recursive: true, force: true });
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
// What node packages/cli/dist/index.js wrote, returned and left on disk for
// each init and matrix argv.
//
// Regenerate with:
//   pnpm build
//   node UseCasesCLI/Scripts/generate-matrix-init-corpus.mjs
enum MatrixInitGoldenCorpus {
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
const target = join(outputDirectory, "MatrixInitGoldenCorpus.swift");
writeFileSync(target, swift);
if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
  throw new Error("MatrixInitGoldenCorpus.swift is not ASCII");
}
console.log(`wrote ${recorded.length} cases to ${target}`);
