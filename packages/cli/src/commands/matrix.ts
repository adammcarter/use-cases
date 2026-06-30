import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { UseCaseQuery } from "@use-cases-plugin/core";
import type { CliCommand, CommandOutput } from "../command/types.js";
import {
  createCliResult,
  errorEnvelope,
  loadUseCaseMatrix,
  mutateUseCaseMatrix,
  queryUseCases,
  replayEvidence,
  resolveContextOrError,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult,
  type ResolvedContext
} from "../runtime.js";
import { componentFlag, dataRootFlag, jsonFlag, repoFlag, workspaceFlags } from "./common.js";

// Shared post-mutation result mapping (the legacy writeMutationResult), returning
// the envelope + exit code instead of writing: ok unless blocked; a path-escape
// diagnostic maps to exit 4, any other block to exit 1.
function mutationOutput(
  command: string,
  result: ReturnType<typeof mutateUseCaseMatrix>,
  context: ResolvedContext
): CommandOutput {
  const ok = result.status !== "blocked";
  const envelope = createCliResult(command, result, {
    ok,
    complete: ok,
    diagnostics: result.diagnostics,
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
  if (ok) {
    return { envelope, exitCode: 0 };
  }
  const pathEscape = result.diagnostics.some((item) => item.code === "matrix.mutation_path_escape");
  return { envelope, exitCode: pathEscape ? 4 : 1 };
}

export const matrixValidateCommand: CliCommand = {
  path: ["matrix", "validate"],
  command: "matrix.validate",
  summary: "Validate the use-case matrix.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "matrix.validate");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const snapshot = loadUseCaseMatrix({ context: context.context });
    return {
      envelope: createCliResult("matrix.validate", toMatrixValidationResult(snapshot), {
        ok: true,
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

export const matrixListCommand: CliCommand = {
  path: ["matrix", "list"],
  command: "matrix.list",
  summary: "Query and list use cases.",
  flags: [
    ...workspaceFlags,
    { key: "value", name: "--value", kind: "string", repeatable: true, valueName: "<tier>", summary: "Filter by value tier (repeatable)." },
    { key: "journeyRole", name: "--journey-role", kind: "string", repeatable: true, valueName: "<role>", summary: "Filter by journey role (repeatable)." },
    { key: "lifecycle", name: "--lifecycle", kind: "string", repeatable: true, valueName: "<state>", summary: "Filter by lifecycle (repeatable)." },
    { key: "host", name: "--host", kind: "string", repeatable: true, valueName: "<surface>", summary: "Filter by host surface (repeatable)." },
    { key: "tag", name: "--tag", kind: "string", repeatable: true, valueName: "<tag>", summary: "Filter by tag (repeatable)." },
    { key: "changedPath", name: "--changed-path", kind: "string", repeatable: true, valueName: "<path>", summary: "Filter by changed path (repeatable)." },
    { key: "strict", name: "--strict", kind: "boolean", summary: "Fail when the matrix is incomplete." }
  ],
  handler: ({ argv, flags }) => {
    const strict = flags.strict as boolean;
    const context = resolveContextOrError(argv, "matrix.list");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const snapshot = loadUseCaseMatrix({ context: context.context });
    const selected = queryUseCases(snapshot, {
      valueTiers: flags.value as UseCaseQuery["valueTiers"],
      journeyRoles: flags.journeyRole as UseCaseQuery["journeyRoles"],
      lifecycles: flags.lifecycle as UseCaseQuery["lifecycles"],
      hostSurfaces: flags.host as UseCaseQuery["hostSurfaces"],
      tagsAny: flags.tag as string[] | undefined,
      changedPaths: flags.changedPath as string[] | undefined
    });
    const ok = strict ? snapshot.complete : true;
    return {
      envelope: createCliResult("matrix.list", toMatrixListResult(snapshot, selected), {
        ok,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: ok ? 0 : 3
    };
  }
};

export const matrixStatusCommand: CliCommand = {
  path: ["matrix", "status"],
  command: "matrix.status",
  summary: "Compose matrix and evidence completeness.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "matrix.status");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const matrix = loadUseCaseMatrix({ context: context.context });
    const evidence = replayEvidence({ context: context.context });
    const data = {
      schema_version: 1,
      complete: matrix.complete && evidence.complete,
      matrix: toMatrixValidationResult(matrix),
      evidence: toEvidenceStatusResult(evidence)
    };
    return {
      envelope: createCliResult("matrix.status", data, {
        ok: data.complete,
        complete: data.complete,
        diagnostics: [...matrix.diagnostics, ...evidence.diagnostics],
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: data.complete ? 0 : 1
    };
  }
};

export const matrixUpsertCommand: CliCommand = {
  path: ["matrix", "upsert"],
  command: "matrix.upsert",
  summary: "Add or update a single use-case row.",
  flags: [
    ...workspaceFlags,
    { key: "file", name: "--file", kind: "string", required: true, valueName: "<path>", summary: "Target use-case file (inside use-cases/)." },
    { key: "useCaseJson", name: "--use-case-json", kind: "string", valueName: "<json>", summary: "Inline JSON for the use-case row." },
    { key: "useCaseFile", name: "--use-case-file", kind: "string", valueName: "<path>", summary: "Read the use-case JSON from a file (alternative to --use-case-json)." },
    { key: "expectedHash", name: "--expected-hash", kind: "string", valueName: "<hash>", summary: "Optimistic-concurrency guard for updates." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "matrix.upsert");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const targetFile = flags.file as string | undefined;
    const inlineJson = flags.useCaseJson as string | undefined;
    const useCaseFile = flags.useCaseFile as string | undefined;
    if (!targetFile || (!inlineJson && !useCaseFile)) {
      return {
        envelope: errorEnvelope("matrix.upsert", "cli_invalid_arguments", "Missing --file or one of --use-case-json / --use-case-file."),
        exitCode: 2
      };
    }
    if (inlineJson && useCaseFile) {
      return {
        envelope: errorEnvelope("matrix.upsert", "cli_invalid_arguments", "Use only one of --use-case-json or --use-case-file."),
        exitCode: 2
      };
    }
    let useCaseJson: string;
    if (useCaseFile) {
      // --use-case-file is a read-only one-shot input (stdin-from-a-file), so it
      // is intentionally NOT containment-restricted: agents pass scratch JSON from
      // /tmp. A non-JSON target simply fails JSON.parse below.
      const useCaseFilePath = resolve(process.cwd(), useCaseFile);
      try {
        useCaseJson = readFileSync(useCaseFilePath, "utf8");
      } catch {
        return {
          envelope: errorEnvelope("matrix.upsert", "matrix.use_case_file_unreadable", `Could not read --use-case-file: ${useCaseFilePath}`),
          exitCode: 2
        };
      }
    } else {
      useCaseJson = inlineJson as string;
    }
    let useCase: Record<string, unknown>;
    try {
      useCase = JSON.parse(useCaseJson) as Record<string, unknown>;
    } catch (error) {
      return {
        envelope: errorEnvelope("matrix.upsert", "matrix.mutation_invalid_json", error instanceof Error ? error.message : String(error)),
        exitCode: 2
      };
    }
    const result = mutateUseCaseMatrix({
      context: context.context,
      operation: "upsert",
      targetFile,
      useCase,
      expectedSemanticHash: (flags.expectedHash as string | undefined) ?? undefined,
      actor: "agent"
    });
    return mutationOutput("matrix.upsert", result, context.context);
  }
};

export const matrixRemoveCommand: CliCommand = {
  path: ["matrix", "remove"],
  command: "matrix.remove",
  summary: "Soft-remove a use-case row.",
  flags: [
    repoFlag,
    dataRootFlag,
    componentFlag,
    { key: "useCase", name: "--use-case", kind: "string", required: true, valueName: "<id>", summary: "Use-case id to remove." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the row is being removed." },
    { key: "expectedHash", name: "--expected-hash", kind: "string", valueName: "<hash>", summary: "Optimistic-concurrency guard." },
    jsonFlag
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "matrix.remove");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const useCaseId = flags.useCase as string | undefined;
    const reason = flags.reason as string | undefined;
    if (!useCaseId || !reason) {
      return {
        envelope: errorEnvelope("matrix.remove", "cli_invalid_arguments", "Missing --use-case or --reason."),
        exitCode: 2
      };
    }
    const result = mutateUseCaseMatrix({
      context: context.context,
      operation: "remove",
      useCaseId,
      reason,
      expectedSemanticHash: (flags.expectedHash as string | undefined) ?? undefined,
      actor: "agent"
    });
    return mutationOutput("matrix.remove", result, context.context);
  }
};

export const matrixCommands: CliCommand[] = [
  matrixValidateCommand,
  matrixListCommand,
  matrixStatusCommand,
  matrixUpsertCommand,
  matrixRemoveCommand
];
