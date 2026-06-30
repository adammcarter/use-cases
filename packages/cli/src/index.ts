#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { runLegacyCli, isMissingCoreModule, MISSING_BUILD_MESSAGE } from "./legacy.js";
import { allCommands } from "./command/registry.js";
import { matchCommand, runRegistryCommand } from "./command/dispatch.js";

// Re-exported for tests/consumers that import them from the CLI entrypoint.
export { isMissingCoreModule, MISSING_BUILD_MESSAGE };

// Entry dispatcher (strangler). A command registered in the declarative registry
// runs through `runRegistryCommand`; everything else falls through to the legacy
// single-file dispatcher unchanged. As commands migrate, the registry grows and
// the legacy path shrinks to nothing — at which point legacy.ts is deleted.
export function runCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
  // The legacy dispatcher intercepts version and help (anywhere in argv, or an
  // empty invocation) BEFORE command dispatch. Preserve that precedence: these
  // never match a registry command, so route them straight to legacy — otherwise
  // `matrix upsert --help` would run the upsert handler instead of scoped help.
  if (isHelpOrVersion(normalizedArgv)) {
    return runLegacyCli(argv);
  }
  const match = matchCommand(allCommands, normalizedArgv);
  if (match === null) {
    return runLegacyCli(argv);
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
