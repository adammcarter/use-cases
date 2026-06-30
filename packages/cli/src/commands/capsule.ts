import type { CliCommand, CommandOutput } from "../command/types.js";
import { numberAfter, valueAfter } from "../args/parse.js";
import {
  createCliResult,
  errorEnvelope,
  loadDemoCapsules,
  planDemoCapsule,
  resolveContextOrError,
  runDemoCapsule,
  type ResolvedContext
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

const capsuleFlag = {
  key: "capsule",
  name: "--capsule",
  kind: "string",
  required: true,
  valueName: "<id>",
  summary: "Capsule id."
} as const;

// Non-writing port of the legacy writeCapsuleRunResult: build the envelope + exit
// code instead of writing. ok unless blocked; a blocked run maps to exit 4 when a
// command cwd-escape diagnostic is present, otherwise 1; an ok run maps to exit 1
// when any command did not match its expected exit code, otherwise 0.
function capsuleRunOutput(
  result: ReturnType<typeof runDemoCapsule>,
  context: ResolvedContext
): CommandOutput {
  const ok = result.outcome !== "blocked";
  const envelope = createCliResult("capsule.run", result, {
    ok,
    complete: result.complete,
    diagnostics: result.diagnostics,
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
  if (!ok) {
    const cwdEscape = result.diagnostics.some((item) => item.code === "capsule.command_cwd_escape");
    return { envelope, exitCode: cwdEscape ? 4 : 1 };
  }
  const exitCode = result.command_results.some((item) => !item.matched_expected_exit_code) ? 1 : 0;
  return { envelope, exitCode };
}

export const capsuleListCommand: CliCommand = {
  path: ["capsule", "list"],
  command: "capsule.list",
  summary: "List demo capsules.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "capsule.list");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const snapshot = loadDemoCapsules({ context: context.context });
    const data = {
      schema_version: 1,
      complete: snapshot.complete,
      capsules: snapshot.capsules.map((entry) => ({
        capsule_id: entry.capsule.capsule_id,
        title: entry.capsule.title,
        mode: entry.capsule.mode,
        audience: entry.capsule.audience,
        timebox_seconds: entry.capsule.timebox_seconds,
        item_count: entry.capsule.items.length,
        path: entry.path,
        semantic_hash: entry.semantic_hash
      }))
    };
    return {
      envelope: createCliResult("capsule.list", data, {
        ok: true,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const capsuleValidateCommand: CliCommand = {
  path: ["capsule", "validate"],
  command: "capsule.validate",
  summary: "Validate demo capsules.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "capsule.validate");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const snapshot = loadDemoCapsules({ context: context.context });
    return {
      envelope: createCliResult("capsule.validate", snapshot, {
        ok: snapshot.complete,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: snapshot.complete ? 0 : 1
    };
  }
};

export const capsulePlanCommand: CliCommand = {
  path: ["capsule", "plan"],
  command: "capsule.plan",
  summary: "Plan a demo capsule.",
  flags: [...workspaceFlags, capsuleFlag],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "capsule.plan");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const capsuleId = valueAfter(argv, "--capsule");
    if (!capsuleId) {
      return {
        envelope: errorEnvelope("capsule.plan", "cli_invalid_arguments", "Missing --capsule."),
        exitCode: 2
      };
    }
    const result = planDemoCapsule({ context: context.context, capsuleId });
    const ok = result.outcome === "generated";
    return {
      envelope: createCliResult("capsule.plan", result, {
        ok,
        complete: result.outcome === "generated" && (result.plan_result?.plan?.complete ?? false),
        diagnostics: result.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: result.outcome === "generated" ? 0 : result.outcome === "integrity_blocked" ? 3 : 1
    };
  }
};

export const capsuleRunCommand: CliCommand = {
  path: ["capsule", "run"],
  command: "capsule.run",
  summary: "Run a demo capsule.",
  flags: [
    ...workspaceFlags,
    capsuleFlag,
    { key: "executeCommands", name: "--execute-commands", kind: "boolean", summary: "Actually execute the capsule commands." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key for the run record." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<timestamp>", summary: "Override the recorded-at timestamp." },
    { key: "commandTimeoutMs", name: "--command-timeout-ms", kind: "integer", valueName: "<ms>", summary: "Per-command execution timeout in milliseconds." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "capsule.run");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const capsuleId = valueAfter(argv, "--capsule");
    if (!capsuleId) {
      return {
        envelope: errorEnvelope("capsule.run", "cli_invalid_arguments", "Missing --capsule."),
        exitCode: 2
      };
    }
    try {
      const result = runDemoCapsule({
        context: context.context,
        capsuleId,
        executeCommands: argv.includes("--execute-commands"),
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? undefined,
        recordedAt: valueAfter(argv, "--recorded-at") ?? undefined,
        commandTimeoutMs: numberAfter(argv, "--command-timeout-ms") ?? undefined
      });
      return capsuleRunOutput(result, context.context);
    } catch (error) {
      const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
      return {
        envelope: errorEnvelope("capsule.run", code, error instanceof Error ? error.message : String(error)),
        exitCode: 1
      };
    }
  }
};

export const capsuleCommands: CliCommand[] = [
  capsuleListCommand,
  capsuleValidateCommand,
  capsulePlanCommand,
  capsuleRunCommand
];
