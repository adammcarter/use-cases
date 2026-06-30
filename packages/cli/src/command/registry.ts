import type { CliCommand } from "./types.js";

// The declarative command registry. Empty for now: every command still falls
// through to the legacy dispatcher. Commands are migrated into this list one
// group at a time (matrix, evidence, showcase, …); each addition is
// parity-verified to stay byte-identical before the next.
export const allCommands: CliCommand[] = [];
