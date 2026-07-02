import type { CliCommand } from "../command/types.js";
import {
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  createCliResult,
  errorEnvelope,
  isValidId,
  loadUseCaseMatrix,
  replayEvidence,
  resolveContextOrError,
  toEvidenceAppendResult,
  toEvidenceStatusResult
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Human-readable note for each derived assurance class. Ported verbatim from the
// legacy `assuranceClassMessage` so the evidence.record info diagnostic stays
// byte-identical.
function assuranceClassMessage(assuranceClass: string): string {
  const note =
    assuranceClass === "reported"
      ? " (self-reported — the weakest assurance tier)"
      : assuranceClass === "observed"
        ? " (observed — stronger than self-reported)"
        : assuranceClass === "reproducible"
          ? " (reproducible via a structured command — the strongest tier)"
          : assuranceClass === "reference"
            ? " (reference link)"
            : "";
  return `Evidence assurance class: ${assuranceClass}${note}.`;
}

export const evidenceRecordCommand: CliCommand = {
  path: ["evidence", "record"],
  command: "evidence.record",
  summary: "Record an evidence event for a use case.",
  flags: [
    ...workspaceFlags,
    { key: "useCase", name: "--use-case", kind: "string", required: true, valueName: "<id>", summary: "Use-case id to attach evidence to." },
    { key: "kind", name: "--kind", kind: "string", valueName: "<kind>", summary: "Evidence kind (defaults to manual_observation)." },
    { key: "result", name: "--result", kind: "string", valueName: "<result>", summary: "Evidence result (defaults to observed)." },
    { key: "summary", name: "--summary", kind: "string", valueName: "<text>", summary: "Human summary of the evidence." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "evidence.record");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const useCaseId = flags.useCase as string | undefined;
    if (!useCaseId) {
      return {
        envelope: errorEnvelope("evidence.record", "evidence.use_case.required", "Missing --use-case."),
        exitCode: 2
      };
    }
    const matrix = loadUseCaseMatrix({ context: context.context });
    const resolved = matrix.resolveUseCase(useCaseId);
    if (resolved.kind !== "resolved") {
      return {
        envelope: errorEnvelope("evidence.record", "evidence.use_case.unresolved", `Use case '${useCaseId}' is ${resolved.kind}.`),
        exitCode: 2
      };
    }
    const kind = (flags.kind as string | undefined) ?? "manual_observation";
    const result = (flags.result as string | undefined) ?? "observed";
    const append = appendEvidenceEvent({
      context: context.context,
      idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:${useCaseId}:${kind}:${result}`,
      target: {
        use_case_id: useCaseId,
        use_case_semantic_hash: resolved.useCase.semanticHash
      },
      kind: kind as Parameters<typeof appendEvidenceEvent>[0]["kind"],
      result: result as Parameters<typeof appendEvidenceEvent>[0]["result"],
      summary: (flags.summary as string | undefined) ?? `Recorded ${kind} evidence for ${useCaseId}.`,
      actorType: "agent",
      hostSurface: "codex.cli"
    });
    // Surface the derived assurance class so the agent immediately sees how strong
    // the evidence is (e.g. a self-reported "pass" is the weakest tier). The
    // append-result data shape is schema-locked, so this rides as an info
    // diagnostic rather than an extra data field.
    const snapshot = replayEvidence({ context: context.context });
    const aggregate = snapshot.aggregates.find((item) => item.evidenceId === append.event.aggregate_id);
    const assuranceClass = (aggregate?.assurance as { class?: string } | undefined)?.class;
    const diagnostics = assuranceClass
      ? [
          {
            code: "evidence.assurance_class",
            severity: "info" as const,
            message: assuranceClassMessage(assuranceClass),
            source_path: null,
            json_pointer: null,
            entity_id: null,
            related_ids: []
          }
        ]
      : [];
    return {
      envelope: createCliResult("evidence.record", toEvidenceAppendResult(append), {
        ok: true,
        complete: true,
        diagnostics,
        workspaceRoot: context.context.workspace_root,
        dataRoot: context.context.data_root,
        componentId: context.context.component_id
      }),
      exitCode: 0
    };
  }
};

export const evidenceStatusCommand: CliCommand = {
  path: ["evidence", "status"],
  command: "evidence.status",
  summary: "Replay and report evidence-ledger completeness.",
  flags: workspaceFlags,
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "evidence.status");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const snapshot = replayEvidence({ context: context.context });
    return {
      envelope: createCliResult("evidence.status", toEvidenceStatusResult(snapshot), {
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

export const evidenceVoidCommand: CliCommand = {
  path: ["evidence", "void"],
  command: "evidence.void",
  summary: "Void an evidence aggregate at its expected head.",
  flags: [
    ...workspaceFlags,
    { key: "evidence", name: "--evidence", kind: "string", required: true, valueName: "<id>", summary: "Evidence aggregate id to void." },
    { key: "expectedHead", name: "--expected-head", kind: "string", required: true, valueName: "<event-id>", summary: "Optimistic-concurrency guard (current head event id)." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the evidence is being voided." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli:void: key)." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "evidence.void");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const evidenceId = flags.evidence as string | undefined;
    const expectedHead = flags.expectedHead as string | undefined;
    const reason = flags.reason as string | undefined;
    if (!evidenceId || !expectedHead || !reason) {
      return {
        envelope: errorEnvelope("evidence.void", "cli_invalid_arguments", "Missing --evidence, --expected-head, or --reason."),
        exitCode: 2
      };
    }
    // SECURITY: reject a user-supplied id that is not a canonical id BEFORE it can
    // become a ledger lookup key. Mirrors the legacy rejectUnsafeId/invalidIdExit.
    if (!isValidId(evidenceId)) {
      return {
        envelope: errorEnvelope(
          "evidence.void",
          "UCM_INVALID_ID",
          `Invalid --evidence '${evidenceId}': must be a canonical id (lowercase, no path separators, no '..').`
        ),
        exitCode: 2
      };
    }
    try {
      const append = appendEvidenceVoidEvent({
        context: context.context,
        evidenceId,
        expectedHeadEventId: expectedHead,
        reason,
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:void:${evidenceId}:${expectedHead}`,
        actorType: "agent",
        hostSurface: "codex.cli"
      });
      return {
        envelope: createCliResult("evidence.void", toEvidenceAppendResult(append), {
          ok: true,
          complete: true,
          workspaceRoot: context.context.workspace_root,
          dataRoot: context.context.data_root,
          componentId: context.context.component_id
        }),
        exitCode: 0
      };
    } catch (error) {
      const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
      const exitCode = code === "evidence_expected_head_mismatch" ? 1 : code === "evidence_ledger_damaged" ? 3 : 6;
      return {
        envelope: errorEnvelope("evidence.void", code, error instanceof Error ? error.message : String(error)),
        exitCode
      };
    }
  }
};

export const evidenceCommands: CliCommand[] = [
  evidenceRecordCommand,
  evidenceStatusCommand,
  evidenceVoidCommand
];
