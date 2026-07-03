import { capsuleCommands } from "../commands/capsule.js";
import { doctorCommands } from "../commands/doctor.js";
import { evidenceCommands } from "../commands/evidence.js";
import { hostCommands } from "../commands/host.js";
import { keygenCommands } from "../commands/keygen.js";
import { markersCommands } from "../commands/markers.js";
import { matrixCommands } from "../commands/matrix.js";
import { migrateCommands } from "../commands/migrate.js";
import { planCommands } from "../commands/plan.js";
import { schemaCommands } from "../commands/schema.js";
import { showcaseCommands } from "../commands/showcase.js";
import { workflowCommands } from "../commands/workflow.js";
import type { CliCommand } from "./types.js";

// The declarative command registry. Anything not listed here falls through to the
// builtins fallback (builtins.ts); each registered command is parity-verified to
// stay byte-identical. Handled as builtins, NOT registry commands: version /
// init / help (bespoke non-envelope output) — kept there permanently.
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
  ...keygenCommands,
  ...showcaseCommands
];
