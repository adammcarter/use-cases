import type { FlagSpec, ParsedFlags } from "../command/types.js";

// Compatibility parser. It reproduces the EXACT semantics of the legacy inline
// helpers it replaces — not a "better" parser — so migrated commands behave
// byte-identically:
//
//   boolean              -> argv.includes("--flag")
//   string  (single)     -> valueAfter:  argv[indexOf("--flag") + 1]  (first occurrence)
//   string  (repeatable) -> valuesAfter: token after EACH "--flag" occurrence
//   integer              -> numberAfter: Number(valueAfter), finite or undefined
//
// Like the originals, a value-bearing flag consumes the next token even when it
// looks like another flag (`--a --b` => a === "--b"). Tightening that is a
// deliberate post-v1 change, not part of this refactor.

function valueAfter(argv: string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) {
    return undefined;
  }
  return argv[index + 1];
}

function valuesAfter(argv: string[], flag: string): string[] | undefined {
  const values: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag && argv[index + 1]) {
      values.push(argv[index + 1]);
    }
  }
  return values.length > 0 ? values : undefined;
}

function numberAfter(argv: string[], flag: string): number | undefined {
  const value = valueAfter(argv, flag);
  if (!value) {
    return undefined;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function parseFlags(argv: string[], flags: readonly FlagSpec[]): ParsedFlags {
  const parsed: ParsedFlags = {};
  for (const flag of flags) {
    if (flag.kind === "boolean") {
      parsed[flag.key] = argv.includes(flag.name);
    } else if (flag.kind === "integer") {
      parsed[flag.key] = numberAfter(argv, flag.name);
    } else if (flag.repeatable) {
      parsed[flag.key] = valuesAfter(argv, flag.name);
    } else {
      parsed[flag.key] = valueAfter(argv, flag.name);
    }
  }
  return parsed;
}
