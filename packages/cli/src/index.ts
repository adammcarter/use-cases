#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { runBuiltinCli, isMissingCoreModule, MISSING_BUILD_MESSAGE } from "./builtins.js";
import { allCommands } from "./command/registry.js";
import { matchCommand, runRegistryCommand } from "./command/dispatch.js";

// Re-exported for tests/consumers that import them from the CLI entrypoint.
export { isMissingCoreModule, MISSING_BUILD_MESSAGE };

// Entry dispatcher. A command registered in the declarative registry runs through
// `runRegistryCommand`; the builtins (version/help/init/schema) and unknown
// commands fall through to `runBuiltinCli` (builtins.ts).
export function runCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
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
  const wantsJson = normalizedArgv.includes("--json");
  return runRegistryCommand(match, normalizedArgv, wantsJson);
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
