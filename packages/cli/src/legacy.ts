// Builtin CLI behaviour that stays OUTSIDE the declarative command registry:
// version, the `--help` usage catalog, `init` scaffolding, and `schema`
// introspection — plus the core loader. These either emit bespoke (non-envelope)
// output or hold CI-signed `@use-case` markers, so they live here as a small,
// marker-stable module. `runLegacyCli` is the builtins-only fallback the registry
// dispatcher (index.ts) delegates to when no registry command matches.
import { resolve } from "node:path";
import { renderEnvelope } from "./render.js";

type UcmCoreModule = typeof import("@use-cases-plugin/core");

const { PUBLIC_SCHEMA_IDS, createCliResult, getVersionInfo, validateFixtureWorkspace, scaffoldWorkspace, isInitTemplate } =
  await loadUcmCore();

// Exported so the registry's runtime module reaches core through the same
// bundled-fallback + friendly-missing-build path (a static import in a command
// module would bypass the diagnostics.contracts.missing_build_hint handler).
export async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@use-cases-plugin/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../core/dist/index.js";
    try {
      return await import(bundledCoreSpecifier) as UcmCoreModule;
    } catch (fallbackError) {
      // The package alias AND the bundled dist both failed to resolve: the
      // compiled core/dist has not been built yet. Surface an actionable hint
      // instead of letting a raw ERR_MODULE_NOT_FOUND stack reach the user.
//: @use-case: diagnostics.contracts.missing_build_hint
      if (isMissingCoreModule(fallbackError)) {
        process.stderr.write(`${MISSING_BUILD_MESSAGE}\n`);
        process.exit(2);
      }
//: @use-case: end diagnostics.contracts.missing_build_hint
      throw fallbackError;
    }
  }
}

export const MISSING_BUILD_MESSAGE =
  "ucp: the compiled core is missing. Run `pnpm build` from the repository root before using the CLI.";

function isMissingCorePackage(error: unknown): boolean {
  return isMissingCoreModule(error) && error instanceof Error && error.message.includes("@use-cases-plugin/core");
}

export function isMissingCoreModule(error: unknown): boolean {
  return (
    error instanceof Error &&
    "code" in error &&
    (error as { code?: unknown }).code === "ERR_MODULE_NOT_FOUND"
  );
}

// Output mode for the whole process. Every command builds the SAME normative
// envelope; `rendered()` is the single choke-point that decides whether the
// caller sees the machine JSON (`--json`) or a human-readable view (the default).
// This is what lets `ucp matrix list` work bare while `--json` stays byte-stable.
let outputJson = false;

type CliEnvelope = ReturnType<typeof createCliResult>;

// Thin wrapper over the shared renderer, bound to this dispatcher's process-wide
// `outputJson` mode. The registry path calls `renderEnvelope` with an explicit
// flag instead.
function rendered(envelope: CliEnvelope): string {
  return renderEnvelope(envelope, outputJson);
}

export function runLegacyCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
  const wantsVersion =
    normalizedArgv.includes("--version") || normalizedArgv.includes("-v") || normalizedArgv[0] === "version";
  const wantsJson = normalizedArgv.includes("--json");
  outputJson = wantsJson;

  if (wantsVersion) {
    if (wantsJson) {
      process.stdout.write(rendered(createCliResult("version", getVersionInfo())));
    } else {
      process.stdout.write(`${getVersionInfo().version}\n`);
    }
    return 0;
  }

  // Discoverability: `ucp`, `ucp --help`, `ucp -h`, and `ucp <command> --help`
  // all print a usage envelope. Agents reliably reach for `--help` first, so a
  // bare or help-flagged invocation must answer with the command/flag catalog
  // rather than the cryptic command.unknown response.
  if (normalizedArgv.length === 0 || normalizedArgv.includes("--help") || normalizedArgv.includes("-h")) {
    return runHelp(normalizedArgv, { json: wantsJson });
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "list") {
    process.stdout.write(
      rendered(
        createCliResult("schema.list", {
          schemas: PUBLIC_SCHEMA_IDS.map((id) => ({ id }))
        })
      )
    );
    return 0;
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "validate-fixtures") {
    const fixture = valueAfter(normalizedArgv, "--fixture") ?? "tests/fixtures/workspaces/minimal-valid";
    const fixturePath = resolve(process.cwd(), fixture);
    const result = validateFixtureWorkspace(fixturePath);
    process.stdout.write(
      rendered(
        createCliResult(
          "schema.validate-fixtures",
          {
            fixture,
            validated_schema_ids: result.validated_schema_ids,
            expected_state: result.expected_state
          },
          {
            ok: result.ok,
            complete: result.complete,
            diagnostics: result.diagnostics,
            dataRoot: fixturePath
          }
        )
      )
    );
    return 0;
  }

  if (normalizedArgv[0] === "init") {
    return runInit(normalizedArgv, wantsJson);
  }


  // No recognized command: instead of a cryptic one-line hint, print the usage
  // envelope scoped to whatever group the caller named (e.g. `matrix`) so they
  // can immediately see the valid subcommands and flags.
  return runHelp(normalizedArgv, { unknown: true, json: wantsJson });
}

type UsageFlag = { flag: string; summary: string };
type UsageEntry = { name: string; summary: string; flags: UsageFlag[] };

const COMMON_FLAGS: UsageFlag[] = [
  { flag: "--repo <path>", summary: "Workspace root (defaults to the current directory)." },
  { flag: "--data-root <path>", summary: "Override the data root (must stay inside --repo)." },
  { flag: "--component <id>", summary: "Select a component within the workspace." },
  { flag: "--json", summary: "Emit the machine-readable JSON result envelope (default output is human-readable)." }
];

const USAGE: UsageEntry[] = [
  { name: "version", summary: "Print the CLI version.", flags: [{ flag: "--json", summary: "Emit the version envelope." }] },
  { name: "schema list", summary: "List the public schema ids.", flags: [{ flag: "--json", summary: "Emit the JSON envelope." }] },
  { name: "schema validate-fixtures", summary: "Validate the bundled fixtures against the published schemas.", flags: [{ flag: "--json", summary: "Emit the JSON envelope." }] },
  {
    name: "init",
    summary: "Scaffold a Use Cases Plugin workspace.",
    flags: [
      { flag: "--repo <path>", summary: "Target directory to scaffold into." },
      { flag: "--template <name>", summary: "generic | js-vitest | python-pytest | go-test." },
      { flag: "--component <id>", summary: "Component id to seed." },
      { flag: "--force", summary: "Overwrite existing scaffold files." },
      { flag: "--json", summary: "Emit the JSON result envelope." }
    ]
  },
  { name: "matrix validate", summary: "Validate the use-case matrix.", flags: COMMON_FLAGS },
  {
    name: "matrix list",
    summary: "Query and list use cases.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--value <tier>", summary: "Filter by value tier (repeatable)." },
      { flag: "--journey-role <role>", summary: "Filter by journey role (repeatable)." },
      { flag: "--lifecycle <state>", summary: "Filter by lifecycle (repeatable)." },
      { flag: "--host <surface>", summary: "Filter by host surface (repeatable)." },
      { flag: "--tag <tag>", summary: "Filter by tag (repeatable)." },
      { flag: "--changed-path <path>", summary: "Filter by changed path (repeatable)." },
      { flag: "--strict", summary: "Fail when the matrix is incomplete." }
    ]
  },
  { name: "matrix status", summary: "Compose matrix and evidence completeness.", flags: COMMON_FLAGS },
  {
    name: "matrix upsert",
    summary: "Add or update a single use-case row.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--file <path>", summary: "Target use-case file (inside use-cases/)." },
      { flag: "--use-case-json <json>", summary: "Inline JSON for the use-case row." },
      { flag: "--use-case-file <path>", summary: "Read the use-case JSON from a file (alternative to --use-case-json)." },
      { flag: "--expected-hash <hash>", summary: "Optimistic-concurrency guard for updates." }
    ]
  },
  {
    name: "matrix remove",
    summary: "Soft-remove a use-case row.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--use-case <id>", summary: "Use-case id to remove." },
      { flag: "--reason <text>", summary: "Why the row is being removed." },
      { flag: "--expected-hash <hash>", summary: "Optimistic-concurrency guard." }
    ]
  },
  {
    name: "plan showcase",
    summary: "Select a showcase presentation plan.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--audience <name>", summary: "Target audience (default reviewer)." },
      { flag: "--timebox <seconds>", summary: "Timebox budget." },
      { flag: "--max-items <n>", summary: "Cap the number of selected items." },
      { flag: "--host <surface>", summary: "Host surface." },
      { flag: "--changed-path <path>", summary: "Bias toward changed paths (repeatable)." },
      { flag: "--strict", summary: "Fail on integrity issues." }
    ]
  },
  {
    name: "plan walkthrough",
    summary: "Select a walkthrough presentation plan.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--audience <name>", summary: "Target audience (default reviewer)." },
      { flag: "--timebox <seconds>", summary: "Timebox budget." },
      { flag: "--max-items <n>", summary: "Cap the number of selected items." }
    ]
  },
  {
    name: "plan cards",
    summary: "Render presentation cards from a plan file.",
    flags: [...COMMON_FLAGS, { flag: "--plan-file <path>", summary: "Plan file inside the workspace." }]
  },
  { name: "capsule list", summary: "List demo capsules.", flags: COMMON_FLAGS },
  { name: "capsule validate", summary: "Validate demo capsules.", flags: COMMON_FLAGS },
  {
    name: "capsule plan",
    summary: "Plan a demo capsule.",
    flags: [...COMMON_FLAGS, { flag: "--capsule <id>", summary: "Capsule id." }]
  },
  {
    name: "capsule run",
    summary: "Run a demo capsule.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--capsule <id>", summary: "Capsule id." },
      { flag: "--execute-commands", summary: "Actually execute the capsule commands." }
    ]
  },
  {
    name: "evidence record",
    summary: "Append an evidence observation to the ledger.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--use-case <id>", summary: "Use-case id the evidence is for." },
      { flag: "--kind <kind>", summary: "Evidence kind (default manual_observation)." },
      { flag: "--result <result>", summary: "pass | fail | inconclusive | observed (default observed)." },
      { flag: "--summary <text>", summary: "Human summary of the observation." },
      { flag: "--idempotency-key <key>", summary: "Idempotency key for the append." }
    ]
  },
  { name: "evidence status", summary: "Replay the evidence ledger state.", flags: COMMON_FLAGS },
  {
    name: "evidence void",
    summary: "Append a terminal void event for an evidence aggregate.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--evidence <id>", summary: "Evidence aggregate id." },
      { flag: "--expected-head <event-id>", summary: "Expected head event id (concurrency guard)." },
      { flag: "--reason <text>", summary: "Why the evidence is being voided." }
    ]
  },
  {
    name: "showcase start",
    summary: "Start a showcase run from a plan or ad hoc selection.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--plan-file <path>", summary: "Plan file inside the workspace." },
      { flag: "--adhoc --select <id>", summary: "Start an ad hoc run for a single use case." }
    ]
  },
  { name: "showcase status", summary: "Replay a showcase run.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }] },
  { name: "showcase record-observation", summary: "Record an observation for a run item.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }, { flag: "--item <plan_item_id>", summary: "Plan item id (from showcase status — NOT the use-case id)." }, { flag: "--text <text>", summary: "What was observed." }] },
  { name: "showcase record-verdict", summary: "Record a verdict for a run item (observation first).", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }, { flag: "--item <plan_item_id>", summary: "Plan item id." }, { flag: "--verdict <v>", summary: "pass | fail | blocked." }, { flag: "--actor <type>", summary: "agent | user (default agent)." }] },
  { name: "showcase decide", summary: "Record a failure decision before finishing.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }, { flag: "--verdict-event <id>", summary: "Failing verdict event id." }, { flag: "--decision <d>", summary: "The decision." }, { flag: "--reason <text>", summary: "Why." }] },
  { name: "showcase pause", summary: "Pause a showcase run.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }] },
  { name: "showcase resume", summary: "Resume a paused run.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }] },
  { name: "showcase finish", summary: "Finish a run; status is derived from events.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }] },
  { name: "showcase approve", summary: "Record an approval (user approval requires a trusted confirmation path).", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }, { flag: "--statement <text>", summary: "Approval statement." }, { flag: "--actor <type>", summary: "agent | user." }] },
  { name: "showcase reject", summary: "Record a rejection.", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }, { flag: "--statement <text>", summary: "Reason." }] },
  { name: "showcase correct", summary: "Append a correction for a mistaken entry (no history edits).", flags: [...COMMON_FLAGS, { flag: "--run <id>", summary: "Run id." }] },
  { name: "host doctor", summary: "Diagnose a host profile.", flags: [...COMMON_FLAGS, { flag: "--host <name>", summary: "claude | codex | copilot | opencode." }] },
  {
    name: "host project",
    summary: "Project host files (dry-run/write/revert).",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--host <name>", summary: "Host to project." },
      { flag: "--dry-run | --write | --revert", summary: "Exactly one mode." }
    ]
  },
  { name: "host conformance", summary: "Check host conformance.", flags: [...COMMON_FLAGS, { flag: "--host <name>", summary: "Host (or --all)." }, { flag: "--all", summary: "Check every supported host." }] },
  { name: "doctor roots", summary: "Report resolved workspace roots (read-only).", flags: COMMON_FLAGS },
  { name: "doctor skills", summary: "Validate skill assets.", flags: COMMON_FLAGS },
  { name: "doctor package", summary: "Inspect a package artifact.", flags: [...COMMON_FLAGS, { flag: "--tarball <path>", summary: "Inspect a tarball." }, { flag: "--installed-root <path>", summary: "Inspect an installed root." }] },
  { name: "workflow mode", summary: "Print the effective advisory workflow mode.", flags: COMMON_FLAGS },
  { name: "workflow set-mode", summary: "Persist the advisory workflow mode.", flags: [...COMMON_FLAGS, { flag: "--mode <mode>", summary: "Advisory workflow mode." }] },
  { name: "migrate test-matrix", summary: "Migrate a legacy TEST-MATRIX.md.", flags: [...COMMON_FLAGS, { flag: "--source <path>", summary: "Source file." }, { flag: "--dry-run | --write", summary: "Migration mode." }, { flag: "--out <dir>", summary: "Output directory." }] },
  {
    name: "bind",
    summary: "Bind a use-case row to a code marker (inserts the marker into the source).",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--row <id>", summary: "Row id to bind." },
      { flag: "--file <path>", summary: "Source file to place the marker in." },
      { flag: "--mode <mode>", summary: "explicit | swift-func." },
      { flag: "--start-line <n>", summary: "Span start line (REQUIRED for --mode explicit)." },
      { flag: "--end-line <n>", summary: "Span end line (REQUIRED for --mode explicit)." },
      { flag: "--line <n>", summary: "Function line (REQUIRED for --mode swift-func)." },
      { flag: "--suffix <s>", summary: "Disambiguating suffix when a file binds more than one row." },
      { flag: "--register-existing", summary: "Register a marker already present in the source." },
      { flag: "--comment-prefix <s>", summary: "Override the line-comment prefix (else inferred from extension/shebang)." },
      { flag: "--dry-run", summary: "Preview the marker placement without writing the source or registry." }
    ]
  },
  {
    name: "scan",
    summary: "Scan code markers against the bindings ledger and report freshness.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--product-root <path>", summary: "Root to scan for markers (default --repo)." },
      { flag: "--policy-mode <mode>", summary: "feature | release | custom." },
      { flag: "--public-key <path>", summary: "Trusted public key to verify proof signatures (else proofs read UNPROVEN)." },
      { flag: "--keyring <path>", summary: "Multi-key public-key registry (alternative to --public-key)." },
      { flag: "--ci", summary: "CI mode (print inferred spans)." }
    ]
  },
  {
    name: "verify",
    summary: "Run each bound row's verifier and write an UNSIGNED results ledger.",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--product-root <path>", summary: "Root for verifier execution (default --repo)." },
      { flag: "--row <id> | --all", summary: "Target row(s)." },
      { flag: "--out <path>", summary: "Write the unsigned results ledger (feed this to `prove --verification-results`). Keep it OUTSIDE the evidence dir." },
      { flag: "--public-key <path>", summary: "Trusted public key." },
      { flag: "--keyring <path>", summary: "Multi-key public-key registry (alternative to --public-key)." }
    ]
  },
  {
    name: "prove",
    summary: "Mint SIGNED proofs from verification results (CI-only signing key).",
    flags: [
      ...COMMON_FLAGS,
      { flag: "--product-root <path>", summary: "Root the proofs are scoped to (default --repo)." },
      { flag: "--row <id> | --all", summary: "Target row(s)." },
      { flag: "--verification-results <path>", summary: "The results file written by `verify --out` (REQUIRED)." },
      { flag: "--trusted-ci", summary: "Mint as the trusted CI prover." },
      { flag: "--signing-key-env <name>", summary: "Env var holding the signing key (CI secret)." },
      { flag: "--key-id <id>", summary: "Signing key id (default trusted-ci)." },
      { flag: "--authority-file <path>", summary: "Explicit CI authority record (JSON)." },
      { flag: "--append", summary: "Append minted proofs to the evidence ledger." },
      { flag: "--refresh", summary: "Re-mint proofs for rows whose context changed." },
      { flag: "--public-key <path> | --keyring <path>", summary: "Trusted key(s) for verification." }
    ]
  },
  { name: "validate-ledger", summary: "Validate the marker evidence ledger (append-only, signatures, schema).", flags: [...COMMON_FLAGS, { flag: "--public-key <path> | --keyring <path>", summary: "Trusted key(s)." }, { flag: "--base-ref <ref>", summary: "Diff base for the append-only check." }] }
];

function selectUsageEntries(tokens: string[]): UsageEntry[] {
  if (tokens.length === 0) {
    return USAGE;
  }
  const prefix = tokens.join(" ");
  const exact = USAGE.filter((entry) => entry.name === prefix || entry.name.startsWith(`${prefix} `));
  if (exact.length > 0) {
    return exact;
  }
  const group = USAGE.filter((entry) => entry.name === tokens[0] || entry.name.startsWith(`${tokens[0]} `));
  return group.length > 0 ? group : USAGE;
}

//: @use-case: diagnostics.contracts.cli_self_documents
function runHelp(argv: string[], options: { unknown?: boolean; json?: boolean } = {}): number {
  const tokens = argv.filter((arg) => !arg.startsWith("-"));
  const commands = selectUsageEntries(tokens);
  const requested = tokens.length > 0 ? tokens.join(" ") : null;
  const unknownMessage = `No recognized command for '${requested ?? "(none)"}'. See the commands listed below or run \`ucp --help\`.`;

  // Default to human-readable text; emit the JSON envelope only on --json. Agents
  // (and people) reach for `--help` first and expect prose, not a minified blob.
  if (!options.json) {
    process.stdout.write(renderHelpText(commands, { unknown: options.unknown, requested, unknownMessage }));
    return options.unknown ? 2 : 0;
  }

  const data = {
    schema_version: 1,
    usage: "ucp <command> [subcommand] [flags] --json",
    requested,
    commands
  };
  const diagnostics = options.unknown
    ? [
        {
          code: "command.unknown",
          severity: "error" as const,
          message: unknownMessage,
          source_path: null,
          json_pointer: null,
          entity_id: null,
          related_ids: []
        }
      ]
    : [];
  process.stdout.write(
    rendered(
      createCliResult("help", data, {
        ok: !options.unknown,
        complete: !options.unknown,
        diagnostics
      })
    )
  );
  return options.unknown ? 2 : 0;
}

// Render the usage catalog as readable text. A single matched command shows its
// full flag list; the broad list stays compact with a pointer to per-command help.
function renderHelpText(
  commands: UsageEntry[],
  options: { unknown?: boolean; requested: string | null; unknownMessage: string }
): string {
  const lines: string[] = [];
  if (options.unknown) {
    lines.push(`error: ${options.unknownMessage}`, "");
  }
  lines.push("ucp — use-cases-plugin CLI", "");
  lines.push("Usage: ucp <command> [subcommand] [flags] [--json]", "");
  const detailed = commands.length <= 3;
  const heading = options.requested ? `Commands matching '${options.requested}':` : "Commands:";
  lines.push(heading);
  const width = Math.min(28, commands.reduce((max, c) => Math.max(max, c.name.length), 0));
  for (const command of commands) {
    lines.push(`  ${command.name.padEnd(width)}  ${command.summary}`);
    if (detailed) {
      for (const f of command.flags) {
        lines.push(`      ${f.flag.padEnd(34)} ${f.summary}`);
      }
    }
  }
  lines.push("");
  if (!detailed) {
    lines.push("Run `ucp <command> --help` for that command's flags.");
  }
  lines.push("Add --json to any command for the machine-readable result envelope.");
  return `${lines.join("\n")}\n`;
}
//: @use-case: end diagnostics.contracts.cli_self_documents

function runInit(argv: string[], wantsJson: boolean): number {
  const repoRoot = resolve(process.cwd(), valueAfter(argv, "--repo") ?? ".");
  const templateRaw = valueAfter(argv, "--template");
  if (templateRaw !== undefined && !isInitTemplate(templateRaw)) {
    return writeError(
      "init",
      "init.unknown_template",
      `Unknown --template '${templateRaw}'. Use one of generic, js-vitest, python-pytest, go-test.`
    );
  }
  const result = scaffoldWorkspace({
    repoRoot,
    template: templateRaw,
    component: valueAfter(argv, "--component") ?? undefined,
    force: argv.includes("--force")
  });
  const ok = result.status === "created";

  if (wantsJson) {
    process.stdout.write(
      rendered(
        createCliResult("init", result, {
          ok,
          complete: ok,
          diagnostics: result.diagnostics,
          workspaceRoot: repoRoot,
          dataRoot: repoRoot,
          componentId: result.component_id
        })
      )
    );
  } else if (ok) {
    const lines = [
      `Scaffolded a Use Cases Plugin workspace in ${repoRoot}`,
      `  template:  ${result.template}`,
      `  component: ${result.component_id}`,
      "  created:",
      ...result.created_files.map((file) => `    - ${file}`),
      "",
      "Next steps:",
      ...result.next_steps.map((step, index) => `  ${index + 1}. ${step}`),
      ""
    ];
    process.stdout.write(`${lines.join("\n")}\n`);
  } else {
    process.stderr.write(`${result.diagnostics[0]?.message ?? "ucp init failed."}\n`);
  }

  if (ok) {
    return 0;
  }
  return result.diagnostics.some((item) => item.code === "init.path_escape") ? 4 : 1;
}















































// ---------------------------------------------------------------------------
// Phase 7 use-case-marker commands (bind / scan / prove / validate-ledger).
// Thin wiring: parse argv, resolve paths + injected key material, call the core.
// ---------------------------------------------------------------------------










// Minimal ULID-shaped id for registry/proof event ids (uniqueness from the tail).


// SECURITY: reject a user-supplied id that is not a canonical id BEFORE it can
// become a filesystem path segment (e.g. showcase-runs/<runId>/events.jsonl) or a
// ledger lookup key. Returns the stable UCP_INVALID_ID / exit-2 invalid-arguments
// envelope. Returns null when the value is safe, so callers read it as a guard.


// SECURITY: bound a user-supplied file path (e.g. --plan-file) to the workspace,
// symlink-safe, BEFORE it is read from disk. Returns the safe absolute path, or an
// { exitCode } carrying the stable UCP_PATH_ESCAPE / exit-4 envelope on escape.

function writeError(command: string, code: string, message: string, exitCode = 2): number {
  process.stdout.write(
    rendered(
      createCliResult(
        command,
        {},
        {
          ok: false,
          complete: false,
          diagnostics: [
            {
              code,
              severity: "error",
              message,
              source_path: null,
              json_pointer: null,
              entity_id: null,
              related_ids: []
            }
          ]
        }
      )
    )
  );
  return exitCode;
}





function valueAfter(argv: string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) {
    return undefined;
  }
  return argv[index + 1];
}



