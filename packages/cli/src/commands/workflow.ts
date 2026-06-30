import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { CliCommand } from "../command/types.js";
import { valueAfter } from "../args/parse.js";
import { createCliResult, errorEnvelope, resolveContextOrError } from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Local legacy helpers ported verbatim. readWorkflowMode/writeWorkflowMode read
// and write the workspace's use-cases-plugin.yml; canonicalWorkflowMode validates
// a requested mode token. Kept identical to the legacy versions so behaviour and
// the on-disk format stay byte-for-byte the same.
function readWorkflowMode(workspaceRoot: string): string {
  const configPath = join(workspaceRoot, "use-cases-plugin.yml");
  const source = readFileSync(configPath, "utf8");
  return source.match(/^default_workflow_mode:\s*([a-z_]+)/m)?.[1] ?? "continuous";
}

function writeWorkflowMode(workspaceRoot: string, mode: string): void {
  const configPath = join(workspaceRoot, "use-cases-plugin.yml");
  const source = readFileSync(configPath, "utf8");
  const next = source.match(/^default_workflow_mode:/m)
    ? source.replace(/^default_workflow_mode:\s*[a-z_]+/m, `default_workflow_mode: ${mode}`)
    : `${source.trimEnd()}\ndefault_workflow_mode: ${mode}\n`;
  const tempPath = `${configPath}.tmp`;
  writeFileSync(tempPath, next);
  renameSync(tempPath, configPath);
}

function canonicalWorkflowMode(value: string | undefined): string | null {
  if (!value) {
    return null;
  }
  const normalized = value.replaceAll("-", "_");
  return ["continuous", "backfill", "showcase_only", "audit_only", "migration", "custom"].includes(normalized)
    ? normalized
    : null;
}

export const workflowSetModeCommand: CliCommand = {
  path: ["workflow", "set-mode"],
  command: "workflow.set-mode",
  summary: "Persist the advisory workflow mode.",
  flags: [
    ...workspaceFlags,
    { key: "mode", name: "--mode", kind: "string", valueName: "<mode>", summary: "Advisory workflow mode." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "workflow.set-mode");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const requested = canonicalWorkflowMode(valueAfter(argv, "--mode"));
    if (!requested) {
      return {
        envelope: errorEnvelope("workflow.set-mode", "workflow_mode_invalid", "Unsupported workflow mode."),
        exitCode: 2
      };
    }
    const previous = readWorkflowMode(context.context.workspace_root);
    const changed = previous !== requested;
    if (changed) {
      writeWorkflowMode(context.context.workspace_root, requested);
    }
    return {
      envelope: createCliResult("workflow.set-mode", {
        schema_version: 1,
        previous_mode: previous,
        configured_mode: requested,
        effective_mode: requested,
        source: "workspace_config",
        advisory: true,
        changed
      }, {
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const workflowModeCommand: CliCommand = {
  path: ["workflow", "mode"],
  command: "workflow.get-mode",
  summary: "Print the effective advisory workflow mode.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "workflow.get-mode");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const mode = readWorkflowMode(context.context.workspace_root);
    return {
      envelope: createCliResult("workflow.get-mode", {
        schema_version: 1,
        effective_mode: mode,
        source: mode === "continuous" ? "default_or_config" : "workspace_config",
        advisory: true
      }, {
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const workflowCommands: CliCommand[] = [
  workflowSetModeCommand,
  workflowModeCommand
];
