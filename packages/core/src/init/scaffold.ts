// `uc init` — scaffold a minimal, WORKING Use Cases workspace.
//
// Takes a brand-new repo from nothing to a bindable, verifiable matrix in one
// command: a workspace config (`use-cases.yml`) wired to a default
// verifier matching the chosen template, plus a `use-cases/` dir holding one
// example row that VALIDATES against the use-case-file schema. The scaffolded
// workspace passes `uc matrix validate` out of the box.
//
// SAFETY: never generates or writes any private key, never writes a GitHub
// workflow file. If a `use-cases.yml` already exists it REFUSES unless
// `force` is set (a `blocked` result, never a silent clobber). All writes are
// path-contained inside the repo root.

import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { diagnostic, type Diagnostic } from "../schema/index.js";
import { isValidId, resolveContainedPath } from "../roots.js";

export const INIT_TEMPLATES = ["generic", "js-vitest", "python-pytest", "go-test"] as const;
export type InitTemplate = (typeof INIT_TEMPLATES)[number];

export function isInitTemplate(value: unknown): value is InitTemplate {
  return typeof value === "string" && (INIT_TEMPLATES as readonly string[]).includes(value);
}

export type ScaffoldWorkspaceOptions = {
  // Absolute or cwd-relative path to the target repo (default: process.cwd()).
  repoRoot: string;
  template?: InitTemplate;
  component?: string;
  force?: boolean;
  // ISO date written into the AGENTS.md decision (default: today).
  today?: string;
};

export type ScaffoldWorkspaceResult = {
  schema_version: 1;
  status: "created" | "blocked";
  template: InitTemplate;
  component_id: string;
  // Verifier the scaffolded `verifiers.default` points at, surfaced so callers
  // (and tests) can report exactly what was wired per template.
  default_verifier: { id: string; kind: "preset" | "script"; preset?: string; command?: string[] };
  created_files: string[];
  // The once-per-repo decision the use-case-driven-development skill reads.
  agents_md: { status: "created" | "appended" | "already_recorded"; decision: "yes" | "no" | "unknown" } | null;
  // Where the git hooks landed and whether core.hooksPath now points at them.
  git_hooks: { hooks_dir: string; hooks_path_set: boolean; extended: string[] } | null;
  next_steps: string[];
  diagnostics: Diagnostic[];
};

const CONFIG_FILE = "use-cases.yml";
const USE_CASE_FILE = join("use-cases", "example.yml");
const DEFAULT_VERIFIER_ID = "acceptance";

// The example row id scaffolded in `use-cases/example.yml`. The js-vitest
// runnable example binds its marked source span to this id, and the acceptance
// test lives at the path the `js.vitest` preset derives from it
// (`tests/use-cases/<row-id>.test.ts`).
const EXAMPLE_ROW_ID = "example.feature.happy_path";
const JS_VITEST_SRC_FILE = join("src", "example.ts");
const JS_VITEST_TEST_FILE = join("tests", "use-cases", `${EXAMPLE_ROW_ID}.test.ts`);
type InitPackageManager = "pnpm" | "yarn" | "npm" | "bun" | "none";

const PACKAGE_MANAGER_LOCKFILES: { packageManager: InitPackageManager; lockfile: string }[] = [
  { packageManager: "pnpm", lockfile: "pnpm-lock.yaml" },
  { packageManager: "yarn", lockfile: "yarn.lock" },
  { packageManager: "npm", lockfile: "package-lock.json" },
  { packageManager: "bun", lockfile: "bun.lockb" }
];

// A template-specific extra file to write (relative path + rendered body).
type TemplateFile = { relPath: string; body: string };

// Transient output the tool itself produces. Neither is durable evidence — the
// signed ledger is — so both must stay out of git. Left untracked and unignored,
// they dirty the adopter's working tree and trip their own clean-tree gates.
const GITIGNORE_FILE = ".gitignore";
const GITIGNORE_ENTRIES: { pattern: string; comment: string }[] = [
  {
    pattern: "showcase-runs/",
    comment: "# use-cases: transient showcase run output (not durable evidence)."
  },
  {
    pattern: ".use-cases/verification-results.jsonl",
    comment: "# use-cases: transient local verification results (the verify -> prove handoff)."
  }
];

// Ensure every entry is present in .gitignore. APPEND-ONLY: an adopter's file is
// never rewritten or reordered, and an entry they already wrote is left alone.
// Returns true when the file was created or modified.
//: @use-case:lifecycle.signals.transient_output_stays_out_of_git
function ensureGitignoreEntries(repoRoot: string): boolean {
  const gitignorePath = join(repoRoot, GITIGNORE_FILE);
  const existing = existsSync(gitignorePath) ? readFileSync(gitignorePath, "utf8") : null;
  const present = new Set(
    (existing ?? "").split("\n").map((line) => line.trim())
  );

  const missing = GITIGNORE_ENTRIES.filter((entry) => !present.has(entry.pattern));
  if (missing.length === 0) {
    return false;
  }

  const additions = missing.flatMap((entry) => [entry.comment, entry.pattern]);
  if (existing === null) {
    writeFileSync(gitignorePath, `${additions.join("\n")}\n`, "utf8");
    return true;
  }

  // Separate our block from whatever the adopter already had, without reflowing it.
  const separator = existing === "" || existing.endsWith("\n") ? "" : "\n";
  const spacer = existing.trim() === "" ? "" : "\n";
  writeFileSync(
    gitignorePath,
    `${existing}${separator}${spacer}${additions.join("\n")}\n`,
    "utf8"
  );
  return true;
}
//: @use-case:end lifecycle.signals.transient_output_stays_out_of_git

export function scaffoldWorkspace(options: ScaffoldWorkspaceOptions): ScaffoldWorkspaceResult {
  const template: InitTemplate = options.template ?? "generic";
  const repoRoot = resolve(options.repoRoot);
  const componentId = deriveComponentId(options.component ?? baseNameOf(repoRoot));
  const verifier = defaultVerifierFor(template);
  const packageManager = detectPackageManager(repoRoot);
  const jsVitestRunCommand = renderJsVitestRunCommand(packageManager, toPosix(JS_VITEST_TEST_FILE));

  const blocked = (diagnostic: Diagnostic): ScaffoldWorkspaceResult => ({
    schema_version: 1,
    status: "blocked",
    template,
    component_id: componentId,
    default_verifier: verifier.summary,
    created_files: [],
    agents_md: null,
    git_hooks: null,
    next_steps: [],
    diagnostics: [diagnostic]
  });

  // Template-specific runnable-example files (e.g. js-vitest ships a marked
  // source file + a matching vitest test so `verify` works out of the box).
  const templateFiles = templateFilesFor(template, jsVitestRunCommand);

  // Path-containment: every write target must stay inside the repo root.
  let configPath: string;
  let useCasePath: string;
  let templatePaths: { relPath: string; absPath: string; body: string }[];
  try {
    configPath = resolveContainedPath(repoRoot, CONFIG_FILE, "Scaffold target escapes the repo boundary.");
    useCasePath = resolveContainedPath(repoRoot, USE_CASE_FILE, "Scaffold target escapes the repo boundary.");
    templatePaths = templateFiles.map((file) => ({
      relPath: file.relPath,
      absPath: resolveContainedPath(repoRoot, file.relPath, "Scaffold target escapes the repo boundary."),
      body: file.body
    }));
  } catch (error) {
    return blocked(
      diagnostic(
        "init.path_escape",
        error instanceof Error ? error.message : "Scaffold target escapes the repo boundary."
      )
    );
  }

  if (existsSync(configPath) && !options.force) {
    return blocked(
      diagnostic(
        "init.workspace_exists",
        `A workspace config already exists at ${CONFIG_FILE}. Re-run with --force to overwrite.`,
        CONFIG_FILE
      )
    );
  }

  const configBody = renderConfig(componentId, verifier);
  const useCaseBody = renderExampleUseCase();

  mkdirSync(dirname(useCasePath), { recursive: true });
  writeFileSync(configPath, configBody, "utf8");
  writeFileSync(useCasePath, useCaseBody, "utf8");

  for (const file of templatePaths) {
    mkdirSync(dirname(file.absPath), { recursive: true });
    writeFileSync(file.absPath, file.body, "utf8");
  }

  const gitignoreTouched = ensureGitignoreEntries(repoRoot);
  const agentsMd = ensureAgentsMdDecision(repoRoot, options.today ?? new Date().toISOString().slice(0, 10));
  const gitHooks = ensureGitHooks(repoRoot);

  return {
    schema_version: 1,
    status: "created",
    template,
    component_id: componentId,
    default_verifier: verifier.summary,
    created_files: [
      toPosix(relative(repoRoot, configPath)),
      toPosix(relative(repoRoot, useCasePath)),
      ...templatePaths.map((file) => toPosix(relative(repoRoot, file.absPath))),
      ...(gitignoreTouched ? [GITIGNORE_FILE] : []),
      ...(agentsMd.status === "already_recorded" ? [] : [AGENTS_MD_FILE]),
      ...gitHooks.written
    ],
    agents_md: { status: agentsMd.status, decision: agentsMd.decision },
    git_hooks: { hooks_dir: gitHooks.hooks_dir, hooks_path_set: gitHooks.hooks_path_set, extended: gitHooks.extended },
    next_steps: nextSteps({ hooksPathSet: gitHooks.hooks_path_set, hooksDir: gitHooks.hooks_dir }),
    diagnostics: []
  };
}

// ---------------------------------------------------------------------------
// AGENTS.md — the once-per-repo decision.
//
// `use-case-driven-development` reads this section first, on every host, and
// never asks again while it exists. init writes `yes` because running init IS
// the decision; an existing section (yes or no) is left exactly as it is.
const AGENTS_MD_FILE = "AGENTS.md";
const DECISION_HEADING = "## Use-case driven development";

//: @use-case:plugin.init.records_decision_in_agents_md#code
function ensureAgentsMdDecision(
  repoRoot: string,
  today: string
): { status: "created" | "appended" | "already_recorded"; decision: "yes" | "no" | "unknown" } {
  const path = join(repoRoot, AGENTS_MD_FILE);
  const existing = existsSync(path) ? readFileSync(path, "utf8") : null;

  if (existing !== null && existing.includes(DECISION_HEADING)) {
    const after = existing.slice(existing.indexOf(DECISION_HEADING) + DECISION_HEADING.length);
    const answer = after.match(/^\s*(yes|no)\b/m)?.[1];
    return { status: "already_recorded", decision: answer === "yes" || answer === "no" ? answer : "unknown" };
  }

  const section = [
    DECISION_HEADING,
    "",
    `yes — ${today}`,
    "",
    "This repo is use-case driven: every functional change starts in `use-cases/`,",
    "rows are agreed before tests, tests and code are wrapped in the row's markers,",
    "and `uc scan` is the coverage number. The rules live in the Use Cases plugin's",
    "skills — `use-case-driven-development` for when and in what order, `use-cases`",
    "for the commands — and every agent working here follows them.",
    ""
  ].join("\n");

  if (existing === null) {
    writeFileSync(path, `# ${baseNameOf(repoRoot)}\n\n${section}`, "utf8");
    return { status: "created", decision: "yes" };
  }
  const separator = existing.endsWith("\n") ? "" : "\n";
  const spacer = existing.trim() === "" ? "" : "\n";
  writeFileSync(path, `${existing}${separator}${spacer}${section}`, "utf8");
  return { status: "appended", decision: "yes" };
}
//: @use-case:end plugin.init.records_decision_in_agents_md#code

// ---------------------------------------------------------------------------
// Git hooks — enforcement from the first commit.
//
// pre-commit blocks on what is simply wrong (invalid matrix, ledger, or a marker
// that disagrees with its binding); pre-push only reports. Pushing red is
// legitimate in the loop, so nothing before LAND refuses a push for a row that
// is merely not green yet. A repo that already routes hooks elsewhere keeps its
// directory and its scripts; the use-cases block is appended, never replacing.
const DEFAULT_HOOKS_DIR = ".githooks";
const HOOK_BLOCK_MARKER = "# use-cases:";

const UC_LOOKUP = [
  "# The plugin puts uc on PATH in Claude sessions; elsewhere set UC to <plugin>/bin/uc.",
  'uc="${UC:-$(command -v uc 2>/dev/null || true)}"',
  'if [ -z "$uc" ]; then',
  '  echo "pre-commit: uc not found — install the Use Cases plugin (https://github.com/adammcarter/use-cases) or set UC=<plugin>/bin/uc" >&2',
  "  exit 0",
  "fi"
];

function preCommitBlock(): string[] {
  return [
    `${HOOK_BLOCK_MARKER} the matrix and its ledgers have to be well-formed to land at all.`,
    'if [ -f "$(git rev-parse --show-toplevel)/use-cases.yml" ]; then',
    ...UC_LOOKUP.map((line) => `  ${line}`.replace(/^  $/, "")),
    '  root="$(git rev-parse --show-toplevel)"',
    '  "$uc" matrix validate --repo "$root" --json >/dev/null \\',
    '    || { echo "pre-commit: use-case matrix invalid — run: uc matrix validate --repo ." >&2; exit 1; }',
    '  key=""; [ -f "$root/.use-cases/trusted-ci-public-key.pem" ] && key="--public-key $root/.use-cases/trusted-ci-public-key.pem"',
    '  "$uc" validate-ledger --repo "$root" $key --json >/dev/null \\',
    '    || { echo "pre-commit: use-case ledger invalid — run: uc validate-ledger --repo ." >&2; exit 1; }',
    "  # A marker and its binding that disagree is INVALID; stale is fine here.",
    '  if "$uc" scan --repo "$root" --json 2>/dev/null | grep -Eq \'"status": *"INVALID"\'; then',
    '    echo "pre-commit: a use-case marker and its binding disagree — run: uc scan --repo ." >&2',
    "    exit 1",
    "  fi",
    "fi"
  ];
}

function prePushBlock(): string[] {
  return [
    `${HOOK_BLOCK_MARKER} say which bound rows this push touches and where they stand. Advisory only.`,
    'if [ -f "$(git rev-parse --show-toplevel)/use-cases.yml" ]; then',
    ...UC_LOOKUP.map((line) => `  ${line}`.replace("pre-commit:", "pre-push:")),
    '  root="$(git rev-parse --show-toplevel)"',
    '  "$uc" impact --repo "$root" 2>/dev/null || true',
    '  "$uc" scan --repo "$root" 2>/dev/null | tail -n 20 || true',
    "fi",
    "exit 0"
  ];
}

//: @use-case:plugin.init.wires_git_hooks#code
function ensureGitHooks(repoRoot: string): { hooks_dir: string; hooks_path_set: boolean; written: string[]; extended: string[] } {
  const isGitRepo = spawnSync("git", ["rev-parse", "--git-dir"], { cwd: repoRoot, encoding: "utf8" }).status === 0;
  const configured = isGitRepo
    ? spawnSync("git", ["config", "--get", "core.hooksPath"], { cwd: repoRoot, encoding: "utf8" }).stdout.trim()
    : "";
  const hooksDir = configured || DEFAULT_HOOKS_DIR;
  const written: string[] = [];
  const extended: string[] = [];

  for (const [name, block] of [["pre-commit", preCommitBlock()], ["pre-push", prePushBlock()]] as const) {
    const relPath = toPosix(join(hooksDir, name));
    const absPath = resolveContainedPath(repoRoot, relPath, "Hook target escapes the repo boundary.");
    mkdirSync(dirname(absPath), { recursive: true });
    if (existsSync(absPath)) {
      const existing = readFileSync(absPath, "utf8");
      if (existing.includes(HOOK_BLOCK_MARKER)) continue;
      // Their hook keeps running first; ours follows. A trailing `exit` in
      // theirs would skip ours, which is their call, not a clobber.
      const separator = existing.endsWith("\n") ? "" : "\n";
      writeFileSync(absPath, `${existing}${separator}\n${block.join("\n")}\n`, "utf8");
      extended.push(relPath);
    } else {
      writeFileSync(absPath, `#!/usr/bin/env bash\n${block.join("\n")}\n`, "utf8");
      written.push(relPath);
    }
    chmodSync(absPath, 0o755);
  }

  let hooksPathSet = false;
  if (isGitRepo && !configured) {
    hooksPathSet = spawnSync("git", ["config", "core.hooksPath", DEFAULT_HOOKS_DIR], { cwd: repoRoot }).status === 0;
  }
  return { hooks_dir: hooksDir, hooks_path_set: hooksPathSet, written, extended };
}
//: @use-case:end plugin.init.wires_git_hooks#code

type VerifierPlan = {
  // The YAML body for the `acceptance` verifier entry (indented two extra spaces
  // beyond the verifiers map), plus a structured summary for the result envelope.
  yaml: string[];
  summary: ScaffoldWorkspaceResult["default_verifier"];
};

function detectPackageManager(repoRoot: string): InitPackageManager {
  for (const candidate of PACKAGE_MANAGER_LOCKFILES) {
    if (existsSync(join(repoRoot, candidate.lockfile))) {
      return candidate.packageManager;
    }
  }
  return "none";
}

function renderJsVitestRunCommand(packageManager: InitPackageManager, testPath: string): string {
  switch (packageManager) {
    case "pnpm":
      return `pnpm -s vitest run ${testPath}`;
    case "yarn":
      return `yarn vitest run ${testPath}`;
    case "npm":
      return `npm exec -- vitest run ${testPath}`;
    case "bun":
      return `bun x vitest run ${testPath}`;
    case "none":
    default:
      return `npx vitest run ${testPath}`;
  }
}

function defaultVerifierFor(template: InitTemplate): VerifierPlan {
  const preset = (id: string): VerifierPlan => ({
    yaml: [`    preset: ${id}`, "    evidence_kind: test_result"],
    summary: { id: DEFAULT_VERIFIER_ID, kind: "preset", preset: id }
  });
  switch (template) {
    case "js-vitest":
      return preset("js.vitest");
    case "python-pytest":
      return preset("python.pytest");
    case "go-test":
      return preset("go.test");
    case "generic":
    default: {
      // command.generic ships no command, so the placeholder lives here as an
      // explicit script verifier. `false` makes it FAIL until configured, so a
      // placeholder can never accidentally mint a passing proof. `{slug}` is
      // substituted with the row id at run time.
      const command = ["false", "TODO-replace-with-your-verifier-command-for-{slug}"];
      return {
        yaml: [
          "    # TODO: replace this placeholder with the real command that verifies a row.",
          "    # `{slug}` is substituted with the row id at run time. It exits non-zero",
          "    # until you configure it, so a placeholder can never mint a passing proof.",
          "    kind: script",
          "    evidence_kind: test_result",
          `    command: [${command.map((part) => JSON.stringify(part)).join(", ")}]`
        ],
        summary: { id: DEFAULT_VERIFIER_ID, kind: "script", command }
      };
    }
  }
}

function renderConfig(componentId: string, verifier: VerifierPlan): string {
  return [
    "schema_version: 1",
    `workspace_id: ${componentId}`,
    `component_id: ${componentId}`,
    "data_root: .",
    "use_cases_dir: use-cases",
    "evidence_dir: evidence",
    "demo_capsules_dir: demo-capsules",
    "showcase_runs_dir: showcase-runs",
    "default_workflow_mode: continuous",
    "# Verifiers map a row's required_verifiers id to a real command. `default` is",
    "# used by any row that does not name its own verifier. See docs/cli.md.",
    "verifiers:",
    `  default: ${DEFAULT_VERIFIER_ID}`,
    `  ${DEFAULT_VERIFIER_ID}:`,
    ...verifier.yaml,
    ""
  ].join("\n");
}

//: @use-case:plugin.init.vends_sample_matrix#code
function renderExampleUseCase(): string {
  return [
    "schema_version: 1",
    "# A worked example of one use-case row. Copy it for your first real row, then",
    "# delete this one. One row is one behaviour; its scenarios are its tests — each",
    "# scenario below becomes exactly one test, written before the code.",
    "feature:",
    "  id: example.feature",
    "  name: Example feature",
    "  summary: A sample use case vended by `uc init` — copy its shape for your own rows.",
    "metadata:",
    "  owner: unassigned",
    "  lifecycle: active",
    "use_cases:",
    "  - id: example.feature.happy_path",
    "    title: Example happy path",
    "    # planned while the row is agreed but unproven; active once tests are green",
    "    # and both the test and the code are wrapped in this row's markers.",
    "    lifecycle: active",
    "    # How much the product depends on this: critical | core | supporting | long_tail.",
    "    value_tier: core",
    "    # Where it sits in the user's journey: golden | alternate | edge | negative | failure.",
    "    journey_role: golden",
    "    # How often users hit it: common | occasional | rare.",
    "    usage_frequency: common",
    "    tags: [example]",
    "    # Files the behaviour lives in. `uc bind` wraps the exact span with a marker.",
    "    source_refs:",
    "      - kind: file",
    "        path: src/example.ts",
    "    # Who triggers the behaviour: user | agent | script | system.",
    "    actor: user",
    "    # What they are trying to achieve, in one sentence.",
    "    intent: Demonstrate the use-cases row shape so you can copy it.",
    "    # What must already be true before the trigger.",
    "    preconditions:",
    "      - The project is set up.",
    "    # The event that starts the behaviour.",
    "    trigger: The user performs the example action.",
    "    # One golden path, then the bad paths and the edge cases. Each scenario is",
    "    # one test; a test that proves nothing here is a scenario to write first.",
    "    scenarios:",
    "      - id: example.feature.happy_path.golden",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with valid input.",
    "          - Observe the expected result.",
    "      - id: example.feature.happy_path.bad_input",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with invalid input.",
    "          - Observe a clear error and no side effect.",
    "      - id: example.feature.happy_path.edge_empty",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with empty input.",
    "          - Observe the documented empty-input behaviour.",
    "    # What a person can see when the behaviour holds — the acceptance criteria.",
    "    observable_outcomes:",
    "      - The expected result is visible to the user.",
    "      - Invalid input is refused with a clear message.",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    # Which verifier (from use-cases.yml) has to pass for this row to count.",
    "    verification_policy:",
    "      mode: requirements",
    "      requirements:",
    "        - evidence_kind: test_result",
    `          required_verifiers: [${DEFAULT_VERIFIER_ID}]`,
    "          minimum_count: 1",
    "    # Whether a human must sign this row off in a showcase before release.",
    "    approval_policy:",
    "      mode: none",
    ""
  ].join("\n");
}
//: @use-case:end plugin.init.vends_sample_matrix#code

// Extra files that make a template's scaffolded example RUNNABLE out of the
// box. The `generic`, `python-pytest`, and `go-test` templates ship none here
// (python-pytest's runnable example lives under examples/, not the scaffolder);
// js-vitest ships a marked source file + a matching vitest test so that
// `bind --register-existing` + `verify` succeed immediately after `init`.
function templateFilesFor(template: InitTemplate, jsVitestRunCommand: string): TemplateFile[] {
  switch (template) {
    case "js-vitest":
      return [
        { relPath: JS_VITEST_SRC_FILE, body: renderJsVitestSource() },
        { relPath: JS_VITEST_TEST_FILE, body: renderJsVitestTest(jsVitestRunCommand) }
      ];
    default:
      return [];
  }
}

// The implementation the `example.feature.happy_path` row describes, wrapped in
// a Use Cases marker span (`//` is the configured `.ts` comment prefix).
// `bind --register-existing` binds the row to exactly these source lines.
function renderJsVitestSource(): string {
  return [
    "// A tiny, self-contained module an adopter might own. The exported",
    "// function below is the implementation the use-case row",
    `// \`${EXAMPLE_ROW_ID}\` describes. It is wrapped in a Use Cases`,
    "// marker span (the `@use-case` start/end comments) so the matrix can bind",
    "// the row to exactly these source lines. Replace it with your own code.",
    "",
    `//: @use-case:${EXAMPLE_ROW_ID}`,
    "export function greet(name: string): string {",
    '  const trimmed = name.trim();',
    '  if (trimmed === "") {',
    '    throw new Error("name must not be empty");',
    "  }",
    "  return `Hello, ${trimmed}!`;",
    "}",
    `//: @use-case:end ${EXAMPLE_ROW_ID}`,
    ""
  ].join("\n");
}

// A plain vitest module at the path the `js.vitest` preset derives from the row
// id (`tests/use-cases/<row-id>.test.ts`), so `uc verify` runs it as-is.
function renderJsVitestTest(runCommand: string): string {
  return [
    `// Acceptance test for the \`${EXAMPLE_ROW_ID}\` use-case row.`,
    "//",
    "// Run this file directly with",
    `//   ${runCommand}`,
    "// or let `uc verify` invoke the `js.vitest` preset for the row. Replace",
    "// these assertions as you replace the example row with your own use case.",
    'import { describe, expect, test } from "vitest";',
    'import { greet } from "../../src/example.js";',
    "",
    `describe("${EXAMPLE_ROW_ID}", () => {`,
    '  test("greets a named user", () => {',
    '    expect(greet("Ada")).toBe("Hello, Ada!");',
    "  });",
    "",
    '  test("trims surrounding whitespace", () => {',
    '    expect(greet("  Ada  ")).toBe("Hello, Ada!");',
    "  });",
    "",
    '  test("rejects an empty name", () => {',
    '    expect(() => greet("   ")).toThrow();',
    "  });",
    "});",
    ""
  ].join("\n");
}

export function nextSteps(options: { hooksPathSet?: boolean; hooksDir?: string } = {}): string[] {
  return [
    ...(options.hooksPathSet === false && options.hooksDir === DEFAULT_HOOKS_DIR
      ? ["Point git at the hooks once the repo is initialised: `git config core.hooksPath .githooks`."]
      : []),
    "Copy use-cases/example.yml's row for your first real use case, then delete the example.",
    "Run `uc matrix validate --repo . --json` to confirm the matrix is clean.",
    "Bind the implementing code with `uc bind` — code-marker grammar in docs/markers-adoption.md.",
    "Wire the `acceptance` verifier in use-cases.yml to your real test command (docs/cli.md).",
    "Generate an ed25519 keypair — commit the PUBLIC key, keep the PRIVATE key in a CI secret only (docs/security.md).",
    "Let trusted CI mint FRESH proofs with `uc prove` (docs/cli.md, docs/security.md)."
  ];
}

function deriveComponentId(raw: string): string {
  const segments = raw
    .toLowerCase()
    .split(".")
    .map((segment) =>
      segment
        .replace(/[^a-z0-9_-]+/g, "-")
        .replace(/^[-_]+/, "")
        .replace(/[-_]+$/, "")
    )
    .filter((segment) => segment.length > 0 && /^[a-z0-9]/.test(segment));
  const candidate = segments.join(".");
  return isValidId(candidate) ? candidate : "workspace";
}

function baseNameOf(repoRoot: string): string {
  const parts = repoRoot.split(sep).filter((part) => part.length > 0);
  return parts[parts.length - 1] ?? "workspace";
}

function toPosix(path: string): string {
  return path.split(sep).join("/");
}
