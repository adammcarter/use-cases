// Regenerates the workspace init corpus by running every case below through
// the REAL TypeScript, and recording exactly what it returns and writes.
//
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-init-corpus.mjs
//
// Written:
//
//   Tests/UseCasesCoreTests/Initialization/InitializationGoldenCorpus.swift
//     `scaffoldWorkspace` run over real sandboxes -- empty directories, git
//     repositories, existing .gitignore / AGENTS.md / use-cases.yml / hooks,
//     preconfigured core.hooksPath values, symlinks out of the repository, and
//     git missing from PATH -- with the result, or the error thrown, and every
//     file, directory and symlink the sandbox holds afterwards (file modes
//     included), plus the core.hooksPath git reports afterwards.
//
// The script refuses to run when the dist is older than its src. File contents
// are carried as JSON strings and the corpus is ASCII only, so the marker text
// inside init's js-vitest example never appears as a line of its own in this
// repository. git runs with global and system configuration switched off, so a
// user's own core.hooksPath cannot leak into the corpus.
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  readlinkSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = dirname(scriptDirectory);
const repositoryRoot = dirname(packageRoot);
const coreRoot = join(repositoryRoot, "packages/core");
const initializationTestsDirectory = join(packageRoot, "Tests/UseCasesCoreTests/Initialization");

const GIT_ISOLATION = { GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
Object.assign(process.env, GIT_ISOLATION);

for (const [source, built] of [
  ["src/init/scaffold.ts", "dist/init/scaffold.js"]
]) {
  if (statSync(join(coreRoot, built)).mtimeMs < statSync(join(coreRoot, source)).mtimeMs) {
    throw new Error(`${built} is older than ${source}; rebuild packages/core first`);
  }
}

// ---------------------------------------------------------------------------
// Workspace init.

const scaffoldModulePath = join(coreRoot, "dist/init/scaffold.js");
const scaffold = await import(scaffoldModulePath);
const TODAY = "2026-09-17";
const REPOSITORY = "demo-repo";

// Every case runs in a fresh sandbox holding `<repository>` (unless
// `create_repository` is false) and an `outside` directory. Paths in `files`,
// `directories` and `symlinks` are relative to the sandbox; `<repo>` in a
// hooks_path value stands for the repository's absolute path.
const initCases = [
  { name: "generic_empty_non_repository", options: { template: "generic" } },
  { name: "template_omitted_is_generic", options: {} },
  { name: "generic_fresh_git_repository", git: true, options: { template: "generic" } },
  { name: "js_vitest_fresh_git_repository", git: true, options: { template: "js-vitest" } },
  { name: "python_pytest_non_repository", options: { template: "python-pytest" } },
  { name: "go_test_git_repository", git: true, options: { template: "go-test" } },
  { name: "js_vitest_pnpm_lockfile", files: [{ path: "demo-repo/pnpm-lock.yaml", content: "" }], options: { template: "js-vitest" } },
  { name: "js_vitest_yarn_lockfile", files: [{ path: "demo-repo/yarn.lock", content: "" }], options: { template: "js-vitest" } },
  { name: "js_vitest_npm_lockfile", files: [{ path: "demo-repo/package-lock.json", content: "{}" }], options: { template: "js-vitest" } },
  { name: "js_vitest_bun_lockfile", directories: ["demo-repo/bun.lockb"], options: { template: "js-vitest" } },
  {
    name: "js_vitest_pnpm_wins_over_npm",
    files: [{ path: "demo-repo/package-lock.json", content: "{}" }, { path: "demo-repo/pnpm-lock.yaml", content: "" }],
    options: { template: "js-vitest" }
  },
  { name: "lockfile_ignored_by_generic", files: [{ path: "demo-repo/yarn.lock", content: "" }], options: { template: "generic" } },
  { name: "repository_directory_not_yet_created", create_repository: false, options: { template: "js-vitest" } },
  { name: "gitignore_with_trailing_newline", files: [{ path: "demo-repo/.gitignore", content: "node_modules/\ndist/\n" }], options: {} },
  { name: "gitignore_without_trailing_newline", files: [{ path: "demo-repo/.gitignore", content: "node_modules/" }], options: {} },
  { name: "gitignore_empty", files: [{ path: "demo-repo/.gitignore", content: "" }], options: {} },
  { name: "gitignore_whitespace_only", files: [{ path: "demo-repo/.gitignore", content: "  \n\t" }], options: {} },
  {
    name: "gitignore_already_complete",
    files: [{ path: "demo-repo/.gitignore", content: "showcase-runs/\n.use-cases/verification-results.jsonl\n" }],
    options: {}
  },
  {
    name: "gitignore_one_entry_present_with_padding_and_crlf",
    files: [{ path: "demo-repo/.gitignore", content: "a\r\n  showcase-runs/  \r\nb" }],
    options: {}
  },
  {
    name: "gitignore_commented_entry_is_not_present",
    files: [{ path: "demo-repo/.gitignore", content: "# showcase-runs/\n" }],
    options: {}
  },
  {
    name: "existing_config_blocks",
    files: [{ path: "demo-repo/use-cases.yml", content: "schema_version: 1\n" }, { path: "demo-repo/.gitignore", content: "x\n" }],
    git: true,
    options: { template: "js-vitest" }
  },
  {
    name: "existing_config_with_force_is_overwritten",
    files: [{ path: "demo-repo/use-cases.yml", content: "schema_version: 1\n" }, { path: "demo-repo/use-cases/example.yml", content: "old\n" }],
    options: { force: true }
  },
  { name: "existing_config_directory_blocks", directories: ["demo-repo/use-cases.yml"], options: {} },
  {
    name: "existing_config_dangling_symlink_is_absent",
    symlinks: [{ path: "demo-repo/use-cases.yml", target: "missing-target.yml" }],
    options: {}
  },
  {
    name: "use_cases_directory_symlinked_outside_blocks",
    symlinks: [{ path: "demo-repo/use-cases", target: "../outside" }],
    options: {}
  },
  {
    name: "config_symlinked_outside_blocks_before_existence",
    files: [{ path: "outside/use-cases.yml", content: "theirs\n" }],
    symlinks: [{ path: "demo-repo/use-cases.yml", target: "../outside/use-cases.yml" }],
    options: { force: true }
  },
  {
    name: "js_vitest_source_directory_symlinked_outside_blocks",
    symlinks: [{ path: "demo-repo/src", target: "../outside" }],
    options: { template: "js-vitest" }
  },
  {
    name: "generic_ignores_source_directory_symlinked_outside",
    symlinks: [{ path: "demo-repo/src", target: "../outside" }],
    options: { template: "generic" }
  },
  {
    name: "agents_md_with_yes_decision",
    files: [{ path: "demo-repo/AGENTS.md", content: "# Repo\n\n## Use-case driven development\n\nyes \u2014 2025-01-01\n" }],
    options: {}
  },
  {
    name: "agents_md_with_no_decision",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development\n\n  no, thanks\n" }],
    options: {}
  },
  {
    name: "agents_md_heading_without_answer",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development\n\nmaybe later\n" }],
    options: {}
  },
  {
    name: "agents_md_answer_found_on_a_later_line",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development\n\nWe decided:\nno \u2014 for now\n" }],
    options: {}
  },
  {
    name: "agents_md_answer_needs_a_word_boundary",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development\nyesterday\nnobody\n" }],
    options: {}
  },
  {
    name: "agents_md_answer_mid_line_is_not_found",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development: yes\n" }],
    options: {}
  },
  {
    name: "agents_md_heading_appears_twice",
    files: [{ path: "demo-repo/AGENTS.md", content: "## Use-case driven development\nno\n## Use-case driven development\nyes\n" }],
    options: {}
  },
  {
    name: "agents_md_without_heading_or_trailing_newline",
    files: [{ path: "demo-repo/AGENTS.md", content: "# Team rules\n\nBe kind." }],
    options: {}
  },
  { name: "agents_md_empty", files: [{ path: "demo-repo/AGENTS.md", content: "" }], options: {} },
  { name: "agents_md_whitespace_only", files: [{ path: "demo-repo/AGENTS.md", content: "\n\n" }], options: {} },
  {
    name: "configured_hooks_path_is_extended",
    git: true,
    hooks_path: "hooks",
    files: [{ path: "demo-repo/hooks/pre-commit", content: "#!/usr/bin/env bash\necho theirs-ran", mode: 0o644 }],
    options: {}
  },
  {
    name: "configured_hooks_path_equal_to_default",
    git: true,
    hooks_path: ".githooks",
    options: {}
  },
  {
    name: "configured_hooks_path_with_surrounding_spaces",
    git: true,
    hooks_path: "  my hooks  ",
    options: {}
  },
  {
    name: "hook_already_carrying_the_block_is_left_alone",
    files: [
      { path: "demo-repo/.githooks/pre-commit", content: "#!/bin/sh\n# use-cases: mine\n", mode: 0o600 },
      { path: "demo-repo/.githooks/pre-push", content: "#!/bin/sh\necho push\n", mode: 0o600 }
    ],
    options: {}
  },
  {
    name: "configured_absolute_hooks_path_inside_repository",
    git: true,
    hooks_path: "<repo>/absolute-hooks",
    options: {}
  },
  {
    name: "configured_hooks_path_escaping_the_repository_throws",
    git: true,
    hooks_path: "../outside/hooks",
    options: { template: "js-vitest" }
  },
  {
    name: "configured_hooks_path_starting_with_two_dots",
    git: true,
    hooks_path: "..hooks",
    options: {}
  },
  { name: "git_missing_from_path", git: true, git_missing: true, options: {} },
  { name: "component_option_is_normalized", options: { component: "My Component.Sub_Part--" } },
  { name: "component_option_without_valid_segments_is_workspace", options: { component: "---.__" } },
  { name: "component_option_empty_string_is_not_defaulted", options: { component: "" } },
  { name: "repository_name_with_dots_and_case", repository: "My.Repo_Name", options: {} },
  { name: "repository_name_with_empty_segment", repository: "a..b", options: {} },
  { name: "repository_name_starting_with_digits", repository: "123abc", options: {} },
  { name: "repository_name_non_ascii", repository: "\u00dcn\u00efcode Repo", options: {} },
  { name: "repository_name_with_dotted_capital_i", repository: "\u0130stanbul", options: {} }
];

function git(cwd, args) {
  const run = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (run.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${run.stderr}`);
  }
  return run.stdout;
}

function snapshotTree(sandbox) {
  const entries = [];
  const walk = (relativeDirectory) => {
    for (const name of readdirSync(relativeDirectory === "" ? sandbox : join(sandbox, relativeDirectory))) {
      if (name === ".git") {
        continue;
      }
      const path = relativeDirectory === "" ? name : `${relativeDirectory}/${name}`;
      const stats = lstatSync(join(sandbox, path));
      if (stats.isSymbolicLink()) {
        entries.push({ path, kind: "symlink", target: readlinkSync(join(sandbox, path)) });
      } else if (stats.isDirectory()) {
        entries.push({ path, kind: "directory" });
        walk(path);
      } else {
        entries.push({
          path,
          kind: "file",
          mode: (stats.mode & 0o777).toString(8),
          content: readFileSync(join(sandbox, path), "utf8")
        });
      }
    }
  };
  walk("");
  return entries.sort((left, right) => (left.path < right.path ? -1 : left.path > right.path ? 1 : 0));
}

function runScaffoldWithoutGit(options) {
  const program = `
    const { scaffoldWorkspace } = await import(${JSON.stringify(pathToFileURL(scaffoldModulePath).href)});
    const options = JSON.parse(process.argv[1]);
    try {
      process.stdout.write(JSON.stringify({ result: scaffoldWorkspace(options) }));
    } catch (error) {
      process.stdout.write(JSON.stringify({ thrown: { code: error.code ?? null, message: error.message } }));
    }
  `;
  const run = spawnSync(process.execPath, ["--input-type=module", "-e", program, JSON.stringify(options)], {
    encoding: "utf8",
    env: { PATH: "/nonexistent-use-cases-corpus-path", ...GIT_ISOLATION }
  });
  if (run.status !== 0) {
    throw new Error(`child scaffold failed: ${run.stderr}`);
  }
  return JSON.parse(run.stdout);
}

function runInitCase(testCase) {
  const sandbox = mkdtempSync(join(tmpdir(), "use-cases-init-corpus-"));
  try {
    const repository = testCase.repository ?? REPOSITORY;
    const repositoryRoot = join(sandbox, repository);
    const placeholders = (text) => text.split(repositoryRoot).join("<repo>");
    mkdirSync(join(sandbox, "outside"));
    if (testCase.create_repository !== false) {
      mkdirSync(repositoryRoot);
    }
    if (testCase.git) {
      git(repositoryRoot, ["init", "-q"]);
    }
    if (testCase.hooks_path !== undefined) {
      git(repositoryRoot, ["config", "core.hooksPath", testCase.hooks_path.split("<repo>").join(repositoryRoot)]);
    }
    for (const directory of testCase.directories ?? []) {
      mkdirSync(join(sandbox, directory), { recursive: true });
    }
    for (const file of testCase.files ?? []) {
      mkdirSync(dirname(join(sandbox, file.path)), { recursive: true });
      writeFileSync(join(sandbox, file.path), file.content);
      if (file.mode !== undefined) {
        chmodSync(join(sandbox, file.path), file.mode);
      }
    }
    for (const link of testCase.symlinks ?? []) {
      mkdirSync(dirname(join(sandbox, link.path)), { recursive: true });
      symlinkSync(link.target, join(sandbox, link.path));
    }
    const options = { repoRoot: repositoryRoot, today: TODAY, ...testCase.options };
    let outcome;
    if (testCase.git_missing) {
      outcome = runScaffoldWithoutGit(options);
    } else {
      try {
        outcome = { result: scaffold.scaffoldWorkspace(options) };
      } catch (error) {
        outcome = { thrown: { code: error.code ?? null, message: error.message } };
      }
    }
    let hooksPathAfter = null;
    if (testCase.git) {
      const run = spawnSync("git", ["config", "--get", "core.hooksPath"], { cwd: repositoryRoot, encoding: "utf8" });
      hooksPathAfter = run.status === 0 ? placeholders(run.stdout) : null;
    }
    return {
      name: testCase.name,
      setup: {
        repository,
        create_repository: testCase.create_repository !== false,
        git: testCase.git === true,
        git_missing: testCase.git_missing === true,
        hooks_path: testCase.hooks_path ?? null,
        directories: testCase.directories ?? [],
        files: (testCase.files ?? []).map((file) => ({ path: file.path, content: file.content, mode: file.mode ?? null })),
        symlinks: testCase.symlinks ?? []
      },
      options: { today: TODAY, ...testCase.options },
      outcome: JSON.parse(placeholders(JSON.stringify(outcome))),
      tree: snapshotTree(sandbox),
      hooks_path_after: hooksPathAfter
    };
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
  }
}

const initialization = {
  templates: [...scaffold.INIT_TEMPLATES],
  cases: initCases.map(runInitCase),
  next_steps: [
    { options: {}, steps: scaffold.nextSteps() },
    { options: { hooksPathSet: false, hooksDir: ".githooks" }, steps: scaffold.nextSteps({ hooksPathSet: false, hooksDir: ".githooks" }) },
    { options: { hooksPathSet: true, hooksDir: ".githooks" }, steps: scaffold.nextSteps({ hooksPathSet: true, hooksDir: ".githooks" }) },
    { options: { hooksPathSet: false, hooksDir: "hooks" }, steps: scaffold.nextSteps({ hooksPathSet: false, hooksDir: "hooks" }) },
    { options: { hooksDir: ".githooks" }, steps: scaffold.nextSteps({ hooksDir: ".githooks" }) }
  ],
  // What `new Date().toISOString().slice(0, 10)` gives at these instants,
  // the default for `today`.
  today_from_clock: [
    0, 1_789_603_199_999, 1_789_603_200_000, -1, 253_402_300_799_999, 253_402_300_800_000, -62_167_219_200_001
  ].map((milliseconds) => ({ milliseconds, today: new Date(milliseconds).toISOString().slice(0, 10) }))
};

// ---------------------------------------------------------------------------
// Output.

function asciiJson(value) {
  return JSON.stringify(value).replace(
    /[\u007f-\uffff]/g,
    (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`
  );
}

function nameList(propertyName, names) {
  return `  static let ${propertyName}: [String] = [\n${names.map((name) => `    ${asciiJson(name)},`).join("\n")}\n  ]\n\n`;
}

function swiftFile(typeName, body, summary, nameLists, disabledRules) {
  const json = asciiJson(body);
  let pounds = "#";
  while (json.includes(`\\${pounds}`) || json.includes(`"""${pounds}`) || json.includes(`"${pounds}`)) {
    pounds += "#";
  }
  return `// swiftlint:disable ${disabledRules}
// A generated data file: the corpus below is one JSON literal.
// Generated from the TypeScript init code. DO NOT EDIT BY HAND.
//
// ${summary}
//
// Regenerate with:
//   pnpm --filter @adammcarter/use-cases-core build
//   node UseCasesCore/Scripts/generate-init-corpus.mjs
enum ${typeName} {
${nameLists}  /// The corpus itself: one JSON object, ASCII only.
  static let json = ${pounds}"""
  ${json}
  """${pounds}
}

// swiftlint:enable ${disabledRules}
`;
}

function write(directory, name, contents) {
  const target = join(directory, name);
  mkdirSync(directory, { recursive: true });
  writeFileSync(target, contents);
  if (!/^[\x00-\x7f]*$/.test(readFileSync(target, "utf8"))) {
    throw new Error(`${name} is not ASCII`);
  }
  return target;
}

const initializationPath = write(
  initializationTestsDirectory,
  "InitializationGoldenCorpus.swift",
  swiftFile(
    "InitializationGoldenCorpus",
    initialization,
    "What packages/core/dist/init's scaffoldWorkspace returned or threw for each\n// sandbox, and the whole sandbox tree it left behind.",
    nameList("caseNames", initialization.cases.map((item) => item.name)),
    // The recorded file contents hold `{ ... }` runs the closure rule misreads.
    "line_length single_line_closure_body"
  )
);
console.log(`wrote ${initializationPath}: ${initialization.cases.length} init cases`);
