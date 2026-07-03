import type { CliCommand } from "../command/types.js";

// Unknown-flag detection. The CLI historically ignored unrecognised flags, so a
// typo like `--end-lin 20` silently bound the wrong span. We reject unknown flags
// with a clear error — but conservatively: the allowlist is the union of EVERY
// flag any command declares plus the flags handlers read straight off argv
// without a FlagSpec. So a genuine typo is caught, while every real flag the CLI
// understands is accepted (rejecting a valid flag would be worse than the bug).

// Flags read directly from argv by handlers (no FlagSpec) plus the universal
// flags. Keep in sync with a `rg 'valueAfter\(argv|argv.includes' packages/cli`
// sweep if new direct reads are added.
const GLOBAL_FLAGS: readonly string[] = [
  "--json",
  "--help",
  "-h",
  "--version",
  "-v",
  "--strict",
  "--repo",
  "--data-root",
  "--component",
  "--all",
  "--dry-run",
  "--flag",
  "--force",
  "--host",
  "--installed-root",
  "--mode",
  "--out",
  "--revert",
  "--source",
  "--tarball",
  "--template",
  "--write"
];

// The subset of the direct-read globals that consume the following token as their
// value (so a value that happens to start with `--` isn't misread as a flag).
const GLOBAL_VALUE_FLAGS: readonly string[] = [
  "--repo",
  "--data-root",
  "--component",
  "--flag",
  "--host",
  "--installed-root",
  "--mode",
  "--out",
  "--source",
  "--tarball",
  "--template"
];

// Return the unknown flag tokens in argv given the full command set. Empty ⇒ all
// recognised. Values of value-bearing flags are skipped so they can't be mistaken
// for flags; positional args are ignored.
export function findUnknownFlags(argv: readonly string[], commands: readonly CliCommand[]): string[] {
  const known = new Set<string>(GLOBAL_FLAGS);
  const valueBearing = new Set<string>(GLOBAL_VALUE_FLAGS);
  for (const command of commands) {
    for (const flag of command.flags) {
      known.add(flag.name);
      if (flag.kind !== "boolean") {
        valueBearing.add(flag.name);
      }
    }
  }

  const unknown: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--") {
      continue;
    }
    if (valueBearing.has(token)) {
      index += 1; // skip this flag's value
      continue;
    }
    const looksLikeFlag = token.startsWith("--") || /^-[a-zA-Z]$/.test(token);
    if (looksLikeFlag && !known.has(token)) {
      unknown.push(token);
    }
  }
  return unknown;
}
