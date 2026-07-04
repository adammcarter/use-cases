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

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
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

// A template-specific extra file to write (relative path + rendered body).
type TemplateFile = { relPath: string; body: string };

export function scaffoldWorkspace(options: ScaffoldWorkspaceOptions): ScaffoldWorkspaceResult {
  const template: InitTemplate = options.template ?? "generic";
  const repoRoot = resolve(options.repoRoot);
  const componentId = deriveComponentId(options.component ?? baseNameOf(repoRoot));
  const verifier = defaultVerifierFor(template);

  const blocked = (diagnostic: Diagnostic): ScaffoldWorkspaceResult => ({
    schema_version: 1,
    status: "blocked",
    template,
    component_id: componentId,
    default_verifier: verifier.summary,
    created_files: [],
    next_steps: [],
    diagnostics: [diagnostic]
  });

  // Template-specific runnable-example files (e.g. js-vitest ships a marked
  // source file + a matching vitest test so `verify` works out of the box).
  const templateFiles = templateFilesFor(template);

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

  return {
    schema_version: 1,
    status: "created",
    template,
    component_id: componentId,
    default_verifier: verifier.summary,
    created_files: [
      toPosix(relative(repoRoot, configPath)),
      toPosix(relative(repoRoot, useCasePath)),
      ...templatePaths.map((file) => toPosix(relative(repoRoot, file.absPath)))
    ],
    next_steps: nextSteps(),
    diagnostics: []
  };
}

type VerifierPlan = {
  // The YAML body for the `acceptance` verifier entry (indented two extra spaces
  // beyond the verifiers map), plus a structured summary for the result envelope.
  yaml: string[];
  summary: ScaffoldWorkspaceResult["default_verifier"];
};

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

function renderExampleUseCase(): string {
  return [
    "schema_version: 1",
    "# TODO: replace this example with a real use case for your project.",
    "# Each row describes one observable behaviour your product must keep working.",
    "# Once you bind it to code (`uc bind`) and CI proves it, the row reaches FRESH.",
    "feature:",
    "  id: example.feature",
    "  name: Example feature",
    "  summary: An example use case scaffolded by `uc init` — replace it with your own.",
    "metadata:",
    "  owner: unassigned",
    "  lifecycle: active",
    "use_cases:",
    "  - id: example.feature.happy_path",
    "    title: Example happy path",
    "    lifecycle: active",
    "    value_tier: core",
    "    journey_role: golden",
    "    usage_frequency: common",
    "    tags: [example]",
    "    source_refs:",
    "      - kind: file",
    "        path: src/example.ts",
    "    actor: user",
    "    intent: Demonstrate the use-cases row shape so you can replace it.",
    "    preconditions:",
    "      - The project is set up.",
    "    trigger: The user performs the example action.",
    "    scenarios:",
    "      - id: example.feature.happy_path.main",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action.",
    "          - Observe the expected result.",
    "    observable_outcomes:",
    "      - The expected result is visible to the user.",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    verification_policy:",
    "      mode: requirements",
    "      requirements:",
    "        - evidence_kind: test_result",
    `          required_verifiers: [${DEFAULT_VERIFIER_ID}]`,
    "          minimum_count: 1",
    "    approval_policy:",
    "      mode: none",
    ""
  ].join("\n");
}

// Extra files that make a template's scaffolded example RUNNABLE out of the
// box. The `generic`, `python-pytest`, and `go-test` templates ship none here
// (python-pytest's runnable example lives under examples/, not the scaffolder);
// js-vitest ships a marked source file + a matching vitest test so that
// `bind --register-existing` + `verify` succeed immediately after `init`.
function templateFilesFor(template: InitTemplate): TemplateFile[] {
  switch (template) {
    case "js-vitest":
      return [
        { relPath: JS_VITEST_SRC_FILE, body: renderJsVitestSource() },
        { relPath: JS_VITEST_TEST_FILE, body: renderJsVitestTest() }
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
    `//: @use-case: ${EXAMPLE_ROW_ID}`,
    "export function greet(name: string): string {",
    '  const trimmed = name.trim();',
    '  if (trimmed === "") {',
    '    throw new Error("name must not be empty");',
    "  }",
    "  return `Hello, ${trimmed}!`;",
    "}",
    `//: @use-case: end ${EXAMPLE_ROW_ID}`,
    ""
  ].join("\n");
}

// A plain vitest module at the path the `js.vitest` preset derives from the row
// id (`tests/use-cases/<row-id>.test.ts`), so `uc verify` runs it as-is.
function renderJsVitestTest(): string {
  return [
    `// Acceptance test for the \`${EXAMPLE_ROW_ID}\` use-case row.`,
    "//",
    "// The `js.vitest` verifier preset runs this file with",
    `//   pnpm -s vitest run tests/use-cases/${EXAMPLE_ROW_ID}.test.ts`,
    "// (the path the preset derives from the row id). Replace these assertions",
    "// with real ones as you replace the example row with your own use case.",
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

export function nextSteps(): string[] {
  return [
    "Edit use-cases/example.yml — replace the example row with a real use case.",
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

