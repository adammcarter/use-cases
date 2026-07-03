// `ucm init` — scaffold a minimal, WORKING Use Case Matrix workspace.
//
// Takes a brand-new repo from nothing to a bindable, verifiable matrix in one
// command: a workspace config (`use-case-matrix.yml`) wired to a default
// verifier matching the chosen template, plus a `use-cases/` dir holding one
// example row that VALIDATES against the use-case-file schema. The scaffolded
// workspace passes `ucm matrix validate` out of the box.
//
// SAFETY: never generates or writes any private key, never writes a GitHub
// workflow file. If a `use-case-matrix.yml` already exists it REFUSES unless
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

const CONFIG_FILE = "use-case-matrix.yml";
const USE_CASE_FILE = join("use-cases", "example.yml");
const DEFAULT_VERIFIER_ID = "acceptance";

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

  // Path-containment: every write target must stay inside the repo root.
  let configPath: string;
  let useCasePath: string;
  try {
    configPath = resolveContainedPath(repoRoot, CONFIG_FILE, "Scaffold target escapes the repo boundary.");
    useCasePath = resolveContainedPath(repoRoot, USE_CASE_FILE, "Scaffold target escapes the repo boundary.");
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

  return {
    schema_version: 1,
    status: "created",
    template,
    component_id: componentId,
    default_verifier: verifier.summary,
    created_files: [toPosix(relative(repoRoot, configPath)), toPosix(relative(repoRoot, useCasePath))],
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
    "# Once you bind it to code (`ucm bind`) and CI proves it, the row reaches FRESH.",
    "feature:",
    "  id: example.feature",
    "  name: Example feature",
    "  summary: An example use case scaffolded by `ucm init` — replace it with your own.",
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
    "    intent: Demonstrate the use-case-matrix row shape so you can replace it.",
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

export function nextSteps(): string[] {
  return [
    "Edit use-cases/example.yml — replace the example row with a real use case.",
    "Run `ucm matrix validate --repo . --json` to confirm the matrix is clean.",
    "Bind the implementing code with `ucm bind` — code-marker grammar in docs/markers-adoption.md.",
    "Wire the `acceptance` verifier in use-case-matrix.yml to your real test command (docs/cli.md).",
    "Generate an ed25519 keypair — commit the PUBLIC key, keep the PRIVATE key in a CI secret only (docs/security.md).",
    "Let trusted CI mint FRESH proofs with `ucm prove` (docs/cli.md, docs/security.md)."
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

