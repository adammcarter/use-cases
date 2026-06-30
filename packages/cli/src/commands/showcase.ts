import type { CliCommand, CommandOutput } from "../command/types.js";
import { numberAfter, valueAfter } from "../args/parse.js";
import {
  appendShowcaseApproval,
  appendShowcaseFailureDecision,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  containedPathOrError,
  correctShowcaseVerdict,
  createCliResult,
  errorEnvelope,
  finishShowcaseRun,
  isValidId,
  loadPresentationPlanFile,
  loadUseCaseMatrix,
  pauseShowcaseRun,
  rejectShowcaseApproval,
  replayEvidence,
  replayShowcaseRun,
  resolveContextOrError,
  resumeShowcaseRun,
  selectShowcasePlan,
  startShowcaseRun,
  type ResolvedContext
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// Non-writing port of the legacy `writeShowcaseResult`: wrap a showcase run
// result in the canonical envelope (ok=true, complete from the run status) and
// pair it with the verb's exit code instead of writing to stdout.
function showcaseResultOutput(
  command: string,
  result: ReturnType<typeof startShowcaseRun>,
  context: ResolvedContext,
  exitCode: number
): CommandOutput {
  return {
    envelope: createCliResult(command, result, {
      ok: true,
      complete: result.status.complete,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }),
    exitCode
  };
}

// Non-writing port of the legacy `writeCaughtShowcaseError`: map a thrown core
// error to its diagnostic code/message and exit code (ledger damage -> 3, else
// 1), returning the envelope instead of writing.
function showcaseCaughtError(command: string, error: unknown): CommandOutput {
  const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
  return {
    envelope: errorEnvelope(command, code, error instanceof Error ? error.message : String(error)),
    exitCode: code === "showcase_ledger_damaged" ? 3 : 1
  };
}

// SECURITY: reject a user-supplied id that is not a canonical id BEFORE it can
// become a filesystem path segment (e.g. showcase-runs/<runId>/events.jsonl) or a
// ledger lookup key. Mirrors the legacy rejectUnsafeId/invalidIdExit: returns the
// stable UCP_INVALID_ID / exit-2 envelope, or null when the value is safe.
function rejectUnsafeId(command: string, paramName: string, value: string): CommandOutput | null {
  return isValidId(value)
    ? null
    : {
        envelope: errorEnvelope(
          command,
          "UCP_INVALID_ID",
          `Invalid ${paramName} '${value}': must be a canonical id (lowercase, no path separators, no '..').`
        ),
        exitCode: 2
      };
}

export const showcaseStartCommand: CliCommand = {
  path: ["showcase", "start"],
  command: "showcase.start",
  summary: "Start a showcase run from a plan file or an ad hoc selection.",
  flags: [
    ...workspaceFlags,
    { key: "planFile", name: "--plan-file", kind: "string", valueName: "<path>", summary: "Plan file to start the run from (inside the workspace)." },
    { key: "adhoc", name: "--adhoc", kind: "boolean", summary: "Build an ad hoc plan instead of reading --plan-file." },
    { key: "select", name: "--select", kind: "string", valueName: "<id>", summary: "Use-case id to select for the ad hoc plan." },
    { key: "audience", name: "--audience", kind: "string", valueName: "<audience>", summary: "Ad hoc plan audience (defaults to reviewer)." },
    { key: "timebox", name: "--timebox", kind: "integer", valueName: "<seconds>", summary: "Ad hoc plan timebox in seconds (defaults to 600)." },
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Ad hoc plan generation timestamp." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the start event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.start");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const planFile = valueAfter(argv, "--plan-file");
    if (planFile) {
      const contained = containedPathOrError("showcase.start", contextResult.workspace_root, planFile);
      if (contained.kind === "error") {
        return { envelope: contained.envelope, exitCode: contained.exitCode };
      }
      const planPath = contained.path;
      try {
        const plan = loadPresentationPlanFile(planPath);
        const result = startShowcaseRun({
          context: contextResult,
          plan,
          controlMode: "agent_led",
          actorType: "agent",
          hostSurface: "codex.cli",
          idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:start-plan:${plan.plan_content_hash}`,
          recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:00:00.000Z"
        });
        return showcaseResultOutput("showcase.start", result, contextResult, 0);
      } catch (error) {
        return showcaseCaughtError("showcase.start", error);
      }
    }
    const selected = valueAfter(argv, "--select");
    if (!argv.includes("--adhoc") || !selected) {
      return {
        envelope: errorEnvelope("showcase.start", "showcase.plan_required", "Only --adhoc --select is supported in P6."),
        exitCode: 2
      };
    }
    const matrix = loadUseCaseMatrix({ context: contextResult });
    const evidence = replayEvidence({ context: contextResult });
    const planResult = selectShowcasePlan({
      context: contextResult,
      matrix,
      evidence,
      request: {
        audience: valueAfter(argv, "--audience") ?? "reviewer",
        timeboxSeconds: numberAfter(argv, "--timebox") ?? 600,
        maxItems: 1,
        hostSurface: "codex.cli",
        requestedUseCaseIds: [selected],
        generatedAt: valueAfter(argv, "--generated-at") ?? "2026-06-25T12:00:00.000Z",
        freshnessEvaluatedAt: valueAfter(argv, "--generated-at") ?? "2026-06-25T12:00:00.000Z"
      }
    });
    if (!planResult.plan || !planResult.plan.selected_items.some((item) => item.use_case_id === selected)) {
      return {
        envelope: errorEnvelope("showcase.start", "showcase.selected_use_case_unavailable", "Selected use case was not available for an ad hoc plan."),
        exitCode: 1
      };
    }
    try {
      const result = startShowcaseRun({
        context: contextResult,
        plan: planResult.plan,
        controlMode: "agent_led",
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:start:${selected}:${Date.now()}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:00:00.000Z"
      });
      return showcaseResultOutput("showcase.start", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.start", error);
    }
  }
};

export const showcaseRecordObservationCommand: CliCommand = {
  path: ["showcase", "record-observation"],
  command: "showcase.record-observation",
  summary: "Append an observation to a showcase run plan item.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "item", name: "--item", kind: "string", required: true, valueName: "<id>", summary: "Plan item id." },
    { key: "text", name: "--text", kind: "string", required: true, valueName: "<text>", summary: "Observation text." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the observation event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.record-observation");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const planItemId = valueAfter(argv, "--item");
    const text = valueAfter(argv, "--text");
    if (!runId || !planItemId || !text) {
      return {
        envelope: errorEnvelope("showcase.record-observation", "cli_invalid_arguments", "Missing --run, --item, or --text."),
        exitCode: 2
      };
    }
    const invalidObservationId =
      rejectUnsafeId("showcase.record-observation", "--run", runId) ??
      rejectUnsafeId("showcase.record-observation", "--item", planItemId);
    if (invalidObservationId !== null) {
      return invalidObservationId;
    }
    try {
      const result = appendShowcaseObservation({
        context: contextResult,
        runId,
        planItemId,
        text,
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:observation:${runId}:${planItemId}:${text}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:01:00.000Z"
      });
      return showcaseResultOutput("showcase.record-observation", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.record-observation", error);
    }
  }
};

export const showcaseRecordVerdictCommand: CliCommand = {
  path: ["showcase", "record-verdict"],
  command: "showcase.record-verdict",
  summary: "Append a verdict to a showcase run plan item.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "item", name: "--item", kind: "string", required: true, valueName: "<id>", summary: "Plan item id." },
    { key: "verdict", name: "--verdict", kind: "string", required: true, valueName: "<verdict>", summary: "Verdict value." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the verdict event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.record-verdict");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const planItemId = valueAfter(argv, "--item");
    const verdict = valueAfter(argv, "--verdict");
    if (!runId || !planItemId || !verdict) {
      return {
        envelope: errorEnvelope("showcase.record-verdict", "cli_invalid_arguments", "Missing --run, --item, or --verdict."),
        exitCode: 2
      };
    }
    const invalidVerdictId =
      rejectUnsafeId("showcase.record-verdict", "--run", runId) ??
      rejectUnsafeId("showcase.record-verdict", "--item", planItemId);
    if (invalidVerdictId !== null) {
      return invalidVerdictId;
    }
    const status = replayShowcaseRun({ context: contextResult, runId });
    const item = status.items.find((candidate) => candidate.plan_item_id === planItemId);
    if (!item?.latest_observation_event_id) {
      return {
        envelope: errorEnvelope("showcase.record-verdict", "showcase.verdict_requires_observation", "Verdict requires a prior observation."),
        exitCode: 1
      };
    }
    try {
      const result = appendShowcaseVerdict({
        context: contextResult,
        runId,
        planItemId,
        verdict: verdict as Parameters<typeof appendShowcaseVerdict>[0]["verdict"],
        observationEventIds: [item.latest_observation_event_id],
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseVerdict>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:verdict:${runId}:${planItemId}:${verdict}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:00.000Z"
      });
      return showcaseResultOutput("showcase.record-verdict", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.record-verdict", error);
    }
  }
};

export const showcaseDecideCommand: CliCommand = {
  path: ["showcase", "decide"],
  command: "showcase.decide",
  summary: "Record a failure decision against a showcase verdict event.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "verdictEvent", name: "--verdict-event", kind: "string", required: true, valueName: "<event-id>", summary: "Verdict event id the decision targets." },
    { key: "decision", name: "--decision", kind: "string", required: true, valueName: "<decision>", summary: "Decision value." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the decision was made." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the decision event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.decide");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const verdictEventId = valueAfter(argv, "--verdict-event");
    const decision = valueAfter(argv, "--decision");
    const reason = valueAfter(argv, "--reason");
    if (!runId || !verdictEventId || !decision || !reason) {
      return {
        envelope: errorEnvelope("showcase.decide", "cli_invalid_arguments", "Missing --run, --verdict-event, --decision, or --reason."),
        exitCode: 2
      };
    }
    const invalidDecideId = rejectUnsafeId("showcase.decide", "--run", runId);
    if (invalidDecideId !== null) {
      return invalidDecideId;
    }
    try {
      const result = appendShowcaseFailureDecision({
        context: contextResult,
        runId,
        verdictEventId,
        decision: decision as Parameters<typeof appendShowcaseFailureDecision>[0]["decision"],
        reason,
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseFailureDecision>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:decision:${runId}:${verdictEventId}:${decision}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:30.000Z"
      });
      return showcaseResultOutput("showcase.decide", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.decide", error);
    }
  }
};

export const showcasePauseCommand: CliCommand = {
  path: ["showcase", "pause"],
  command: "showcase.pause",
  summary: "Pause a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "reason", name: "--reason", kind: "string", valueName: "<text>", summary: "Pause reason (defaults to 'Paused by operator.')." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the pause event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.pause");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const reason = valueAfter(argv, "--reason") ?? "Paused by operator.";
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.pause", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidPauseId = rejectUnsafeId("showcase.pause", "--run", runId);
    if (invalidPauseId !== null) {
      return invalidPauseId;
    }
    try {
      const result = pauseShowcaseRun({
        context: contextResult,
        runId,
        reason,
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof pauseShowcaseRun>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:pause:${runId}:${reason}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:45.000Z"
      });
      return showcaseResultOutput("showcase.pause", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.pause", error);
    }
  }
};

export const showcaseResumeCommand: CliCommand = {
  path: ["showcase", "resume"],
  command: "showcase.resume",
  summary: "Resume a paused showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "reason", name: "--reason", kind: "string", valueName: "<text>", summary: "Resume reason (defaults to 'Resumed by operator.')." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the resume event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.resume");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const reason = valueAfter(argv, "--reason") ?? "Resumed by operator.";
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.resume", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidResumeId = rejectUnsafeId("showcase.resume", "--run", runId);
    if (invalidResumeId !== null) {
      return invalidResumeId;
    }
    try {
      const result = resumeShowcaseRun({
        context: contextResult,
        runId,
        reason,
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof resumeShowcaseRun>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:resume:${runId}:${reason}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:50.000Z"
      });
      return showcaseResultOutput("showcase.resume", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.resume", error);
    }
  }
};

export const showcaseFinishCommand: CliCommand = {
  path: ["showcase", "finish"],
  command: "showcase.finish",
  summary: "Finish a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the finish event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.finish");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.finish", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidFinishId = rejectUnsafeId("showcase.finish", "--run", runId);
    if (invalidFinishId !== null) {
      return invalidFinishId;
    }
    try {
      const result = finishShowcaseRun({
        context: contextResult,
        runId,
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:finish:${runId}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:03:00.000Z"
      });
      return showcaseResultOutput("showcase.finish", result, contextResult, result.status.run_outcome === "passed" ? 0 : 1);
    } catch (error) {
      return showcaseCaughtError("showcase.finish", error);
    }
  }
};

export const showcaseStatusCommand: CliCommand = {
  path: ["showcase", "status"],
  command: "showcase.status",
  summary: "Replay and report a showcase run's status.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.status");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.status", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidStatusId = rejectUnsafeId("showcase.status", "--run", runId);
    if (invalidStatusId !== null) {
      return invalidStatusId;
    }
    const status = replayShowcaseRun({ context: contextResult, runId });
    return {
      envelope: createCliResult("showcase.status", status, {
        ok: true,
        complete: status.complete,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      }),
      exitCode: 0
    };
  }
};

export const showcaseApproveCommand: CliCommand = {
  path: ["showcase", "approve"],
  command: "showcase.approve",
  summary: "Record an approval for a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "statement", name: "--statement", kind: "string", required: true, valueName: "<text>", summary: "Approval statement." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the approval event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.approve");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const statement = valueAfter(argv, "--statement");
    if (!runId || !statement) {
      return {
        envelope: errorEnvelope("showcase.approve", "cli_invalid_arguments", "Missing --run or --statement."),
        exitCode: 2
      };
    }
    const invalidApproveId = rejectUnsafeId("showcase.approve", "--run", runId);
    if (invalidApproveId !== null) {
      return invalidApproveId;
    }
    try {
      const result = appendShowcaseApproval({
        context: contextResult,
        runId,
        decision: "approved",
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseApproval>[0]["actorType"],
        hostSurface: "codex.cli",
        statement,
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:approve:${runId}:${statement}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:00.000Z",
        // SECURITY: the approval authority is HARDCODED to untrusted_automation —
        // an agent driving the CLI cannot mint trusted user sign-off. Ported
        // verbatim from the legacy runShowcaseApprove; do not parameterise.
        authority: { kind: "untrusted_automation" }
      });
      return showcaseResultOutput("showcase.approve", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.approve", error);
    }
  }
};

export const showcaseRejectCommand: CliCommand = {
  path: ["showcase", "reject"],
  command: "showcase.reject",
  summary: "Record a rejection for a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "statement", name: "--statement", kind: "string", required: true, valueName: "<text>", summary: "Rejection statement." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to user)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the rejection event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.reject");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const statement = valueAfter(argv, "--statement");
    if (!runId || !statement) {
      return {
        envelope: errorEnvelope("showcase.reject", "cli_invalid_arguments", "Missing --run or --statement."),
        exitCode: 2
      };
    }
    const invalidRejectId = rejectUnsafeId("showcase.reject", "--run", runId);
    if (invalidRejectId !== null) {
      return invalidRejectId;
    }
    try {
      const result = rejectShowcaseApproval({
        context: contextResult,
        runId,
        actorType: (valueAfter(argv, "--actor") ?? "user") as Parameters<typeof rejectShowcaseApproval>[0]["actorType"],
        hostSurface: "codex.cli",
        statement,
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:reject:${runId}:${statement}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:30.000Z",
        // SECURITY: the rejection authority is HARDCODED to untrusted_automation —
        // an agent driving the CLI cannot mint trusted user sign-off. Ported
        // verbatim from the legacy runShowcaseReject; do not parameterise.
        authority: { kind: "untrusted_automation" }
      });
      return showcaseResultOutput("showcase.reject", result, contextResult, 1);
    } catch (error) {
      return showcaseCaughtError("showcase.reject", error);
    }
  }
};

export const showcaseCorrectCommand: CliCommand = {
  path: ["showcase", "correct"],
  command: "showcase.correct",
  summary: "Correct a previously recorded showcase verdict.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "targetEvent", name: "--target-event", kind: "string", required: true, valueName: "<event-id>", summary: "Verdict event id to correct." },
    { key: "verdict", name: "--verdict", kind: "string", required: true, valueName: "<verdict>", summary: "Corrected verdict value." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the verdict is being corrected." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the correction event." }
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "showcase.correct");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = valueAfter(argv, "--run");
    const targetEventId = valueAfter(argv, "--target-event");
    const correctedVerdict = valueAfter(argv, "--verdict");
    const reason = valueAfter(argv, "--reason");
    if (!runId || !targetEventId || !correctedVerdict || !reason) {
      return {
        envelope: errorEnvelope("showcase.correct", "cli_invalid_arguments", "Missing --run, --target-event, --verdict, or --reason."),
        exitCode: 2
      };
    }
    const invalidCorrectId = rejectUnsafeId("showcase.correct", "--run", runId);
    if (invalidCorrectId !== null) {
      return invalidCorrectId;
    }
    try {
      const result = correctShowcaseVerdict({
        context: contextResult,
        runId,
        targetEventId,
        correctedVerdict: correctedVerdict as Parameters<typeof correctShowcaseVerdict>[0]["correctedVerdict"],
        reason,
        actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof correctShowcaseVerdict>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:correct:${runId}:${targetEventId}:${correctedVerdict}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:45.000Z"
      });
      return showcaseResultOutput("showcase.correct", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.correct", error);
    }
  }
};

export const showcaseCommands: CliCommand[] = [
  showcaseStartCommand,
  showcaseRecordObservationCommand,
  showcaseRecordVerdictCommand,
  showcaseDecideCommand,
  showcasePauseCommand,
  showcaseResumeCommand,
  showcaseFinishCommand,
  showcaseStatusCommand,
  showcaseApproveCommand,
  showcaseRejectCommand,
  showcaseCorrectCommand
];
