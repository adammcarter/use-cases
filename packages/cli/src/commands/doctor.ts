import { accessSync, constants } from "node:fs";
import { resolve } from "node:path";
import type { CliCommand } from "../command/types.js";
import { valueAfter } from "../args/parse.js";
import {
  createCliResult,
  errorEnvelope,
  inspectPackageArtifact,
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

export const doctorPackageCommand: CliCommand = {
  path: ["doctor", "package"],
  command: "doctor.package",
  summary: "Inspect the packaged plugin artifact (maintainer-only; builds via pnpm).",
  hidden: true,
  flags: [
    ...workspaceFlags,
    { key: "tarball", name: "--tarball", kind: "string", valueName: "<path>", summary: "Inspect a packed tarball instead of the workspace." },
    { key: "installedRoot", name: "--installed-root", kind: "string", valueName: "<path>", summary: "Inspect an installed plugin root instead of the workspace." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "doctor.package");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const tarball = valueAfter(argv, "--tarball");
    const installedRoot = valueAfter(argv, "--installed-root");
    if (tarball && installedRoot) {
      return {
        envelope: errorEnvelope("doctor.package", "package.target_conflict", "Use only one of --tarball or --installed-root."),
        exitCode: 2
      };
    }
    try {
      const data = inspectPackageArtifact({
        target: tarball
          ? { kind: "tarball", path: resolve(process.cwd(), tarball) }
          : installedRoot
            ? { kind: "installed_root", path: resolve(process.cwd(), installedRoot) }
            : { kind: "workspace", path: context.context.workspace_root, build: true }
      });
      const envelope = createCliResult("doctor.package", data, {
        ok: data.complete,
        complete: data.complete,
        diagnostics: data.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      });
      // Derive the exit code from the FINAL envelope's `ok`, not `data.complete`.
      // createCliResult forces ok:false when an error-severity diagnostic is present
      // even if data.complete is true — so keying off data.complete could ship an
      // ok:false envelope with exit 0 (a false green). ok is the exit-code contract.
      return {
        envelope,
        exitCode: envelope.ok ? 0 : 1
      };
    } catch (error) {
      return {
        envelope: errorEnvelope("doctor.package", "package.inspection_failed", error instanceof Error ? error.message : String(error)),
        exitCode: 2
      };
    }
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
  doctorPackageCommand,
  doctorRootsCommand
];
