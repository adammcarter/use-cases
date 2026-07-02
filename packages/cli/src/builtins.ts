// Builtin CLI behaviour that stays OUTSIDE the declarative command registry:
// version, the `--help` usage catalog, `init` scaffolding, and `schema`
// introspection. These emit bespoke (non-envelope) output or hold a CI-signed
// `@use-case` marker (cli_self_documents, in the help machinery), so they live
// here as a small, marker-stable module. `runBuiltinCli` is the builtins-only
// fallback the registry dispatcher (index.ts) delegates to when no registry
// command matches. The core loader lives in ./coreLoader.ts.
import { resolve } from "node:path";
import { loadUcmCore } from "./coreLoader.js";
import { valueAfter } from "./args/parse.js";
import { renderEnvelope } from "./render.js";
import { allCommands } from "./command/registry.js";
import { buildUsageCatalog, type UsageEntry } from "./command/help-catalog.js";

const { PUBLIC_SCHEMA_IDS, createCliResult, getVersionInfo, validateFixtureWorkspace, scaffoldWorkspace, isInitTemplate } =
  await loadUcmCore();

// Output mode for the whole process. Every command builds the SAME normative
// envelope; `rendered()` is the single choke-point that decides whether the
// caller sees the machine JSON (`--json`) or a human-readable view (the default).
// This is what lets `ucm matrix list` work bare while `--json` stays byte-stable.
let outputJson = false;

type CliEnvelope = ReturnType<typeof createCliResult>;

// Thin wrapper over the shared renderer, bound to this dispatcher's process-wide
// `outputJson` mode. The registry path calls `renderEnvelope` with an explicit
// flag instead.
function rendered(envelope: CliEnvelope): string {
  return renderEnvelope(envelope, outputJson);
}

export function runBuiltinCli(argv: string[]): number {
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

  // Discoverability: `ucm`, `ucm --help`, `ucm -h`, and `ucm <command> --help`
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

// The usage catalog is DERIVED from the declarative command registry (one
// FlagSpec source of truth) rather than re-typed here. buildUsageCatalog prefixes
// the non-registry builtins (version / init) onto the projected registry commands.
const USAGE: UsageEntry[] = buildUsageCatalog(allCommands);

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
  const unknownMessage = `No recognized command for '${requested ?? "(none)"}'. See the commands listed below or run \`ucm --help\`.`;

  // Default to human-readable text; emit the JSON envelope only on --json. Agents
  // (and people) reach for `--help` first and expect prose, not a minified blob.
  if (!options.json) {
    process.stdout.write(renderHelpText(commands, { unknown: options.unknown, requested, unknownMessage }));
    return options.unknown ? 2 : 0;
  }

  const data = {
    schema_version: 1,
    usage: "ucm <command> [subcommand] [flags] --json",
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
  lines.push("ucm — use-case-matrix CLI", "");
  lines.push("Usage: ucm <command> [subcommand] [flags] [--json]", "");
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
    lines.push("Run `ucm <command> --help` for that command's flags.");
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
    process.stderr.write(`${result.diagnostics[0]?.message ?? "ucm init failed."}\n`);
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
// ledger lookup key. Returns the stable UCM_INVALID_ID / exit-2 invalid-arguments
// envelope. Returns null when the value is safe, so callers read it as a guard.


// SECURITY: bound a user-supplied file path (e.g. --plan-file) to the workspace,
// symlink-safe, BEFORE it is read from disk. Returns the safe absolute path, or an
// { exitCode } carrying the stable UCM_PATH_ESCAPE / exit-4 envelope on escape.

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





