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
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

// The argv `--run` performs, taken from everything after a standalone `--`. A
// leading `--` is already stripped by the entrypoint, so only a LATER one is a
// separator here.
function commandAfterSeparator(argv: string[]): string[] {
  const index = argv.indexOf("--", 1);
  return index === -1 ? [] : argv.slice(index + 1);
}

function sha256(input: string): string {
  return `sha256:${createHash("sha256").update(input).digest("hex")}`;
}

type PerformedCommand =
  | { kind: "error"; envelope: unknown }
  | {
      kind: "performed";
      argv: string[];
      exitCode: number;
      stdoutSha256: string;
      stderrSha256: string;
    };

// Spawn the command in the workspace root and distil what was observed. The exit
// code and output digests are the observation; the argv is the part a
// hand-written record cannot honestly produce.
function runPerformedCommand(argv: string[], cwd: string): PerformedCommand {
  const command = commandAfterSeparator(argv);
  if (command.length === 0) {
    return {
      kind: "error",
      envelope: errorEnvelope(
        "evidence.record",
        "evidence.run.command_required",
        "--perform needs a command: `use-cases evidence record --use-case <id> --perform -- <cmd> [args...]`."
      )
    };
  }
  const [executable, ...args] = command;
  const outcome = spawnSync(executable, args, { cwd, encoding: "utf8" });
  // A command that could not start is a failed run, not a crashed CLI: the
  // observation is "this did not work", and it is recorded as such.
  const exitCode = typeof outcome.status === "number" ? outcome.status : 127;
  return {
    kind: "performed",
    argv: command,
    exitCode,
    stdoutSha256: sha256(outcome.stdout ?? ""),
    stderrSha256: sha256(outcome.stderr ?? "")
  };
}

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
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    // NOT `--run`: `showcase --run <id>` already owns that name as a VALUE-bearing
    // flag, so the shared unknown-flag allowlist would treat the `--` separator as
    // its value and swallow the command. Caught by the acceptance test, not by
    // reading the code.
    { key: "perform", name: "--perform", kind: "boolean", summary: "PERFORM the behaviour: everything after `--` is spawned here, and the exit code + output digests become the evidence. Without it, a record is only your word for it." }
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
    // --run: PERFORM the behaviour rather than assert it.
    //
    // Without this, every record the CLI could write was `actor_type: agent` ->
    // `method: reported` -> assurance class `reported`, the ledger's own weakest
    // tier. There was no way for the tool to record that it had SEEN something
    // happen, which is why genuinely driving a behaviour could not move the
    // acceptance claim: the strongest thing an agent could write was still only
    // its word. Here the tool spawns the command itself, so the argv, the exit
    // code and the output digests are observations rather than claims.
    const performed =
      flags.perform === true ? runPerformedCommand(argv, context.context.workspace_root) : null;
    if (performed?.kind === "error") {
      return { envelope: performed.envelope, exitCode: 2 };
    }
    const kind = (flags.kind as string | undefined) ?? (performed ? "command_result" : "manual_observation");
    const result =
      (flags.result as string | undefined) ??
      (performed ? (performed.exitCode === 0 ? "pass" : "fail") : "observed");
    const summary =
      (flags.summary as string | undefined) ??
      (performed
        ? `Ran \`${performed.argv.join(" ")}\` for ${useCaseId}: exit ${performed.exitCode}, ` +
          `stdout ${performed.stdoutSha256}, stderr ${performed.stderrSha256}.`
        : `Recorded ${kind} evidence for ${useCaseId}.`);
    const append = appendEvidenceEvent({
      context: context.context,
      idempotencyKey:
        (flags.idempotencyKey as string | undefined) ??
        (performed
          ? `cli:run:${useCaseId}:${performed.stdoutSha256}:${performed.exitCode}`
          : `cli:${useCaseId}:${kind}:${result}`),
      target: {
        use_case_id: useCaseId,
        use_case_semantic_hash: resolved.useCase.semanticHash
      },
      kind: kind as Parameters<typeof appendEvidenceEvent>[0]["kind"],
      result: result as Parameters<typeof appendEvidenceEvent>[0]["result"],
      summary,
      // `script` is what makes this a structured_command observation rather than
      // a reported one, and the argv below is what proves a command existed.
      actorType: performed ? "script" : "agent",
      ...(performed
        ? { method: { type: "structured_command" as const, executable: performed.argv[0], argv: performed.argv } }
        : {}),
      hostSurface: "codex.cli"
    });
    // Surface the derived assurance class so the agent immediately sees how strong
    // the evidence is (e.g. a self-reported "pass" is the weakest tier). The
    // append-result data shape is schema-locked, so this rides as an info
    // diagnostic rather than an extra data field.
    const snapshot = replayEvidence({ context: context.context });
    const aggregate = snapshot.aggregates.find((item) => item.evidenceId === append.event.aggregate_id);
    const assuranceClass = (aggregate?.assurance as { class?: string } | undefined)?.class;
    // What was actually run, said back. A performed run's whole value is that the
    // tool saw it happen, so the reader gets the argv and the exit code rather
    // than having to trust a summary line.
    const runDiagnostics = performed
      ? [
          {
            code: "evidence.performed_run",
            severity: "info" as const,
            message:
              `Performed \`${performed.argv.join(" ")}\` and observed exit ${performed.exitCode}.`,
            source_path: null,
            json_pointer: null,
            entity_id: null,
            related_ids: []
          }
        ]
      : [];
    const diagnostics = assuranceClass
      ? [
          ...runDiagnostics,
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
      : runDiagnostics;
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
