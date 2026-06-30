import { matrixCommands } from "../commands/matrix.js";
import { schemaCommands } from "../commands/schema.js";
import type { CliCommand } from "./types.js";

// The declarative command registry. Commands are migrated off the legacy
// dispatcher one group at a time; anything not listed here still falls through to
// legacy.ts. Each addition is parity-verified to stay byte-identical.
//
// Still on the legacy path: version/init/help (bespoke non-envelope output),
// plan, capsule, evidence, workflow, migrate, host, doctor, showcase, markers.
export const allCommands: CliCommand[] = [...schemaCommands, ...matrixCommands];
