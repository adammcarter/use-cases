import type { FlagSpec } from "../command/types.js";

// Flags shared across most commands, defined once so help and parsing never
// drift between groups. Summaries match the legacy USAGE table verbatim.
export const repoFlag: FlagSpec = {
  key: "repo",
  name: "--repo",
  kind: "string",
  valueName: "<path>",
  summary: "Workspace root (defaults to the current directory)."
};

export const dataRootFlag: FlagSpec = {
  key: "dataRoot",
  name: "--data-root",
  kind: "string",
  valueName: "<path>",
  summary: "Override the data root (must stay inside --repo)."
};

export const componentFlag: FlagSpec = {
  key: "component",
  name: "--component",
  kind: "string",
  valueName: "<id>",
  summary: "Select a component within the workspace."
};

export const jsonFlag: FlagSpec = {
  key: "json",
  name: "--json",
  kind: "boolean",
  summary: "Emit the machine-readable JSON result envelope (default output is human-readable)."
};

// The workspace-context trio + --json, the COMMON_FLAGS of the legacy USAGE table.
export const workspaceFlags: readonly FlagSpec[] = [repoFlag, dataRootFlag, componentFlag, jsonFlag];
