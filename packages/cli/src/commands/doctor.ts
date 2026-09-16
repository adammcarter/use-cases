import { accessSync, constants } from "node:fs";
import type { CliCommand } from "../command/types.js";
import {
  createCliResult,
  errorEnvelope,
  resolveContextOrError,
  validateSkillAssets
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Local port of the legacy `canWrite`: probe a directory for write access without
// mutating it, swallowing the EACCES/ENOENT throw into a boolean.
function canWrite(path: string): boolean {
  try {
    accessSync(path, constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

export const doctorSkillsCommand: CliCommand = {
  path: ["doctor", "skills"],
  command: "doctor.skills",
  summary: "Validate packaged skill assets (maintainer-only; expects a plugin checkout).",
  hidden: true,
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "doctor.skills");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const result = validateSkillAssets({ context: context.context });
    return {
      envelope: createCliResult("doctor.skills", result, {
        ok: result.complete,
        complete: result.complete,
        diagnostics: result.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: result.complete ? 0 : 1
    };
  }
};


export const doctorRootsCommand: CliCommand = {
  path: ["doctor", "roots"],
  command: "doctor.roots",
  summary: "Report the resolved workspace and data roots.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "doctor.roots");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const writable = canWrite(context.context.data_root);
    return {
      envelope: createCliResult("doctor.roots", {
        schema_version: 1,
        workspace_root: context.context.workspace_root,
        data_root: context.context.data_root,
        use_cases_root: context.context.use_cases_root,
        component_id: context.context.component_id,
        config_path: context.context.config_path,
        provenance: context.context.provenance,
        writable
      }, {
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const doctorCommands: CliCommand[] = [
  doctorSkillsCommand,
  doctorRootsCommand
];
