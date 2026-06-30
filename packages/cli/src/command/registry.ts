import { capsuleCommands } from "../commands/capsule.js";
import { doctorCommands } from "../commands/doctor.js";
import { evidenceCommands } from "../commands/evidence.js";
import { hostCommands } from "../commands/host.js";
import { markersCommands } from "../commands/markers.js";
import { matrixCommands } from "../commands/matrix.js";
import { migrateCommands } from "../commands/migrate.js";
import { planCommands } from "../commands/plan.js";
import { schemaCommands } from "../commands/schema.js";
import { showcaseCommands } from "../commands/showcase.js";
import { workflowCommands } from "../commands/workflow.js";
import type { CliCommand } from "./types.js";

// The declarative command registry. Anything not listed here falls through to the
// legacy dispatcher; each migrated command is parity-verified to stay
// byte-identical. Still on the legacy path: version/init/help (bespoke
// non-envelope output) — kept there permanently in phase 10.
export const allCommands: CliCommand[] = [
  ...schemaCommands,
  ...matrixCommands,
  ...planCommands,
  ...capsuleCommands,
  ...evidenceCommands,
  ...workflowCommands,
  ...migrateCommands,
  ...hostCommands,
  ...doctorCommands,
  ...markersCommands,
  ...showcaseCommands
];
