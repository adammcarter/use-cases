#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { runBuiltinCli } from "./builtins.js";
import { isMissingCoreModule, MISSING_BUILD_MESSAGE } from "./coreLoader.js";
import { allCommands } from "./command/registry.js";
import { matchCommand, runRegistryCommand } from "./command/dispatch.js";
import { findUnknownFlags } from "./args/validate.js";
import { renderEnvelope } from "./render.js";
import { caughtErrorEnvelope, errorEnvelope } from "./runtime.js";

// Re-exported for tests/consumers that import them from the CLI entrypoint.
export { isMissingCoreModule, MISSING_BUILD_MESSAGE };

// Entry dispatcher. A command registered in the declarative registry runs through
// `runRegistryCommand`; the builtins (version/help/init/schema) and unknown
// commands fall through to `runBuiltinCli` (builtins.ts).
export function runCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
  const wantsJson = normalizedArgv.includes("--json");
  try {
    // The builtins fallback intercepts version and help (anywhere in argv, or an
    // empty invocation) BEFORE command dispatch. Preserve that precedence: these
    // never match a registry command, so route them straight to the builtins —
    // otherwise `matrix upsert --help` would run the handler instead of scoped help.
    if (isHelpOrVersion(normalizedArgv)) {
      return runBuiltinCli(argv);
    }
    const match = matchCommand(allCommands, normalizedArgv);
    if (match === null) {
      return runBuiltinCli(argv);
    }
    // Reject typo'd/unknown flags with exit 2 instead of silently ignoring them
    // (a mistyped --end-line would otherwise bind the wrong span).
    const unknown = findUnknownFlags(normalizedArgv, allCommands);
    if (unknown.length > 0) {
      const noun = unknown.length > 1 ? "options" : "option";
      process.stdout.write(
        renderEnvelope(errorEnvelope(match.command, "cli_unknown_flag", `Unknown ${noun}: ${unknown.join(", ")}`), wantsJson)
      );
      return 2;
    }
    return runRegistryCommand(match, normalizedArgv, wantsJson);
  } catch (error) {
    // Last-resort guard for anything the registry dispatcher doesn't already wrap
    // (a builtin handler, or a throw during command matching): render the standard
    // ok:false envelope rather than letting a raw stack trace escape to stderr.
    process.stdout.write(renderEnvelope(caughtErrorEnvelope(deriveCommandName(normalizedArgv), error), wantsJson));
    return 1;
  }
}

// Best-effort dotted command id from the leading non-flag tokens, used to label an
// error envelope when a failure occurs before a command produced one of its own.
function deriveCommandName(argv: string[]): string {
  const tokens: string[] = [];
  for (const token of argv) {
    if (token.startsWith("-")) {
      break;
    }
    tokens.push(token);
  }
  return tokens.length > 0 ? tokens.join(".") : "cli";
}

function isHelpOrVersion(normalizedArgv: string[]): boolean {
  return (
    normalizedArgv.length === 0 ||
    normalizedArgv.includes("--help") ||
    normalizedArgv.includes("-h") ||
    normalizedArgv.includes("--version") ||
    normalizedArgv.includes("-v") ||
    normalizedArgv[0] === "version"
  );
}

function isEntrypoint(): boolean {
  if (!process.argv[1]) {
    return false;
  }

  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntrypoint()) {
  process.exitCode = runCli(process.argv.slice(2));
}
