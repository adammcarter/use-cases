import { capsuleCommands } from "../commands/capsule.js";
import { doctorCommands } from "../commands/doctor.js";
import { evidenceCommands } from "../commands/evidence.js";
import { hostCommands } from "../commands/host.js";
import { matrixCommands } from "../commands/matrix.js";
import { migrateCommands } from "../commands/migrate.js";
import { planCommands } from "../commands/plan.js";
import { schemaCommands } from "../commands/schema.js";
import { workflowCommands } from "../commands/workflow.js";
import type { CliCommand } from "./types.js";

// The declarative command registry. Commands are migrated off the legacy
// dispatcher one group at a time; anything not listed here still falls through to
// legacy.ts. Each addition is parity-verified to stay byte-identical.
//
// Still on the legacy path: version/init/help (bespoke non-envelope output),
// showcase, and markers (bind/scan/prove/verify/validate-ledger).
export const allCommands: CliCommand[] = [
  ...schemaCommands,
  ...matrixCommands,
  ...planCommands,
  ...capsuleCommands,
  ...evidenceCommands,
  ...workflowCommands,
  ...migrateCommands,
  ...hostCommands,
  ...doctorCommands
];
