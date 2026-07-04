// The CLI `--help` usage catalog, derived FROM the declarative command registry
// instead of a hand-maintained parallel table. Every registry command already
// carries its summary and FlagSpecs; this module projects those into the
// UsageEntry shape the help renderer (builtins.ts) consumes, so the two can
// never drift. Only the genuinely non-registry builtins (version / init) are
// authored by hand here.
import type { CliCommand, FlagSpec } from "./types.js";

export type UsageFlag = { flag: string; summary: string };
export type UsageEntry = { name: string; summary: string; flags: UsageFlag[] };

// The non-registry builtins (version / init). These emit bespoke, non-envelope
// output and never pass through the registry dispatcher, so they have no
// FlagSpec to derive from — they are authored here verbatim.
export const BUILTIN_USAGE: UsageEntry[] = [
  { name: "version", summary: "Print the CLI version.", flags: [{ flag: "--json", summary: "Emit the version envelope." }] },
  {
    name: "init",
    summary: "Scaffold a Use Cases workspace.",
    flags: [
      { flag: "--repo <path>", summary: "Target directory to scaffold into." },
      { flag: "--template <name>", summary: "generic | js-vitest | python-pytest | go-test." },
      { flag: "--component <id>", summary: "Component id to seed." },
      { flag: "--force", summary: "Overwrite existing scaffold files." },
      { flag: "--json", summary: "Emit the JSON result envelope." }
    ]
  }
];

// Render a single FlagSpec as a usage `flag` string: boolean flags are bare
// (`--ci`), value-bearing flags append their placeholder (`--repo <path>`).
function toUsageFlag(flag: FlagSpec): UsageFlag {
  return {
    flag: flag.kind === "boolean" ? flag.name : `${flag.name} ${flag.valueName ?? ""}`.trim(),
    summary: flag.summary
  };
}

// Project one registry command into a UsageEntry. Hidden flags are dropped from
// the generated help (they stay dispatchable).
function toUsageEntry(command: CliCommand): UsageEntry {
  return {
    name: command.path.join(" "),
    summary: command.summary,
    flags: command.flags.filter((flag) => !flag.hidden).map(toUsageFlag)
  };
}

// The full usage catalog: the hand-authored builtins followed by every registry
// command projected from its declarative spec.
export function buildUsageCatalog(commands: CliCommand[]): UsageEntry[] {
  // Hidden commands stay dispatchable but are omitted from generated help (e.g.
  // maintainer-only release tooling that users should not reach for).
  return [...BUILTIN_USAGE, ...commands.filter((command) => !command.hidden).map(toUsageEntry)];
}
