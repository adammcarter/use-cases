// Declarative command model. Each leaf CLI command is data: a token path, a
// flag spec, and a handler that maps parsed args to a result envelope. Dispatch,
// arg-parsing, and help all derive from this — replacing the legacy if-chains,
// the 175 inline arg reads, and the hand-maintained USAGE table.

export type CommandPath = readonly [string, ...string[]];

export type FlagKind = "boolean" | "string" | "integer";

// A single flag. The parser's behaviour deliberately mirrors the legacy helpers
// it replaces: `boolean` ~ `argv.includes("--flag")`, `string`/`integer` ~
// `valueAfter(argv, "--flag")` (consuming the next token even if flag-like),
// and `repeatable` ~ `valuesAfter(argv, "--flag")`.
export interface FlagSpec {
  // Stable key on the parsed flags object (e.g. "dataRoot" for "--data-root").
  readonly key: string;
  // Primary CLI spelling, including the leading dashes.
  readonly name: `--${string}`;
  readonly kind: FlagKind;
  readonly summary: string;
  // Placeholder shown in help for value-bearing flags, e.g. "<path>".
  readonly valueName?: string;
  // Collect every occurrence (string/integer only) instead of the first.
  readonly repeatable?: boolean;
  // Surfaced in help only; the parser does not itself enforce requiredness.
  readonly required?: boolean;
  // Hidden from generated help (kept dispatchable).
  readonly hidden?: boolean;
}

export type ParsedFlags = Record<string, string | string[] | number | boolean | undefined>;

export interface HandlerContext {
  // The normalized argv (after the leading `--` strip), for handlers that still
  // need raw access during migration.
  readonly argv: string[];
  readonly flags: ParsedFlags;
  readonly json: boolean;
}

// A handler returns the result envelope plus the process exit code. It MUST NOT
// write to stdout/stderr — the dispatcher renders the envelope (JSON or human)
// and returns the exit code, so output stays centralized and byte-identical.
export interface CommandOutput {
  readonly envelope: unknown;
  readonly exitCode: number;
}

export type CliHandler = (context: HandlerContext) => CommandOutput;

export interface CliCommand {
  // CLI token path, e.g. ["matrix", "validate"].
  readonly path: CommandPath;
  // Stable envelope command id, e.g. "matrix.validate" (matches the MCP/core
  // operation id, so a shared registry is a later lift, not a rewrite).
  readonly command: string;
  readonly summary: string;
  readonly flags: readonly FlagSpec[];
  readonly handler: CliHandler;
  readonly hidden?: boolean;
}
