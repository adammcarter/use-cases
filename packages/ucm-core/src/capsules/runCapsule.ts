import { spawnSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import type { Diagnostic } from "../schema/index.js";
import { redactSecrets } from "../redact.js";
import {
  appendShowcaseAction,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  finishShowcaseRun,
  readShowcaseEvents,
  replayShowcaseRun,
  startShowcaseRun
} from "../showcase/index.js";
import { planDemoCapsule } from "./loadCapsule.js";
import type {
  DemoCapsuleCommandResult,
  DemoCapsuleCommandStep,
  DemoCapsulePendingStep,
  DemoCapsuleRunOptions,
  DemoCapsuleRunResult
} from "./types.js";

const DEFAULT_RECORDED_AT = "2026-06-25T12:00:00.000Z";
const DEFAULT_COMMAND_TIMEOUT_MS = 30_000;
const MAX_COMMAND_TIMEOUT_MS = 300_000;
const MAX_CAPTURED_OUTPUT_BYTES = 16_384;
const COMMAND_MAX_BUFFER_BYTES = 1_048_576;

type PlannedCapsuleStep = {
  itemIndex: number;
  stepIndex: number;
  useCaseId: string;
  planItemId: string;
  step: { kind: "instruction"; text: string } | { kind: "observation"; text: string } | DemoCapsuleCommandStep;
};

type ResolvedCommandStep = PlannedCapsuleStep & {
  step: DemoCapsuleCommandStep;
  cwd: string;
};

export function runDemoCapsule(options: DemoCapsuleRunOptions): DemoCapsuleRunResult {
  const actorType = options.actorType ?? "agent";
  const hostSurface = options.hostSurface ?? "codex.cli";
  const recordedAt = options.recordedAt ?? DEFAULT_RECORDED_AT;
  const planResult = planDemoCapsule({ context: options.context, capsuleId: options.capsuleId });
  if (planResult.outcome !== "generated" || !planResult.capsule || !planResult.plan_result?.plan) {
    return blocked(options.capsuleId, planResult.plan_result, planResult.diagnostics);
  }
  if (!planResult.plan_result.plan.complete) {
    return blocked(options.capsuleId, planResult.plan_result, [
      diagnostic("capsule.plan_incomplete", "Capsule plan must be complete before it can be performed.", null, options.capsuleId),
      ...planResult.diagnostics
    ]);
  }

  const plannedSteps = plannedCapsuleSteps(planResult);
  if ("diagnostics" in plannedSteps) {
    return blocked(options.capsuleId, planResult.plan_result, plannedSteps.diagnostics);
  }
  const commandSteps = plannedSteps.filter((entry): entry is PlannedCapsuleStep & { step: DemoCapsuleCommandStep } =>
    entry.step.kind === "command"
  );
  if (options.executeCommands && commandSteps.length > 0 && !planResult.capsule.capsule.permissions.command_execution) {
    return blocked(options.capsuleId, planResult.plan_result, [
      diagnostic(
        "capsule.command_execution_not_permitted",
        "Capsule does not permit command execution.",
        planResult.capsule.path,
        options.capsuleId
      )
    ]);
  }

  const resolvedCommands = options.executeCommands ? resolveCommandSteps(options, commandSteps) : [];
  if ("diagnostics" in resolvedCommands) {
    return blocked(options.capsuleId, planResult.plan_result, resolvedCommands.diagnostics);
  }

  if (options.executeCommands && commandSteps.length > 0) {
    const timeoutMs = options.commandTimeoutMs ?? DEFAULT_COMMAND_TIMEOUT_MS;
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0 || timeoutMs > MAX_COMMAND_TIMEOUT_MS) {
      return blocked(options.capsuleId, planResult.plan_result, [
        diagnostic(
          "capsule.command_timeout_invalid",
          `Command timeout must be between 1 and ${MAX_COMMAND_TIMEOUT_MS} milliseconds.`,
          planResult.capsule.path,
          options.capsuleId
        )
      ]);
    }
  }

  const baseKey = options.idempotencyKey ?? `capsule:${options.capsuleId}:${Date.now()}`;
  const start = startShowcaseRun({
    context: options.context,
    plan: planResult.plan_result.plan,
    controlMode: commandSteps.length > 0 ? "script_led" : "agent_led",
    actorType,
    hostSurface,
    idempotencyKey: `${baseKey}:start`,
    recordedAt
  });
  const runId = start.run_id;
  const eventsWritten = [...start.appended_event_ids];
  const pendingSteps: DemoCapsulePendingStep[] = [];
  const commandResults: DemoCapsuleCommandResult[] = [];
  const commandByStep = new Map(commandSteps.map((step, index) => [stepKey(step), resolvedCommands[index]]));

  for (const entry of plannedSteps) {
    const stepId = `${entry.itemIndex}.${entry.stepIndex}`;
    if (entry.step.kind === "instruction") {
      eventsWritten.push(...appendShowcaseAction({
        context: options.context,
        runId,
        planItemId: entry.planItemId,
        action: {
          kind: "instruction",
          text: entry.step.text,
          source: "demo_capsule",
          item_index: entry.itemIndex,
          step_index: entry.stepIndex
        },
        actorType,
        hostSurface,
        idempotencyKey: `${baseKey}:action:${stepId}`,
        recordedAt
      }).appended_event_ids);
      continue;
    }

    if (entry.step.kind === "observation") {
      eventsWritten.push(...appendShowcaseAction({
        context: options.context,
        runId,
        planItemId: entry.planItemId,
        action: {
          kind: "expected_observation_prompt",
          text: entry.step.text,
          source: "demo_capsule",
          item_index: entry.itemIndex,
          step_index: entry.stepIndex
        },
        actorType,
        hostSurface,
        idempotencyKey: `${baseKey}:expected-observation:${stepId}`,
        recordedAt
      }).appended_event_ids);
      pendingSteps.push({
        item_index: entry.itemIndex,
        step_index: entry.stepIndex,
        use_case_id: entry.useCaseId,
        reason: "runtime_observation_required"
      });
      continue;
    }

    if (!options.executeCommands) {
      pendingSteps.push({
        item_index: entry.itemIndex,
        step_index: entry.stepIndex,
        use_case_id: entry.useCaseId,
        reason: "command_execution_not_requested"
      });
      continue;
    }

    const resolvedCommand = commandByStep.get(stepKey(entry));
    if (!resolvedCommand) {
      continue;
    }
    if (hasCommittedEvent(options.context, runId, `${baseKey}:command-verdict:${stepId}`)) {
      continue;
    }
    const commandResult = runCommandStep(resolvedCommand, options.commandTimeoutMs ?? DEFAULT_COMMAND_TIMEOUT_MS);
    commandResults.push(commandResult);
    eventsWritten.push(...appendShowcaseAction({
      context: options.context,
      runId,
      planItemId: entry.planItemId,
      action: {
        kind: "command",
        executable: entry.step.executable,
        argv: entry.step.argv,
        working_directory: entry.step.working_directory,
        source: "demo_capsule",
        item_index: entry.itemIndex,
        step_index: entry.stepIndex
      },
      actorType: "script",
      hostSurface,
      idempotencyKey: `${baseKey}:command-action:${stepId}`,
      recordedAt
    }).appended_event_ids);
    const observation = appendShowcaseObservation({
      context: options.context,
      runId,
      planItemId: entry.planItemId,
      text: commandObservationText(commandResult),
      actorType: "script",
      hostSurface,
      idempotencyKey: `${baseKey}:command-observation:${stepId}`,
      recordedAt
    });
    eventsWritten.push(...observation.appended_event_ids);
    eventsWritten.push(...appendShowcaseVerdict({
      context: options.context,
      runId,
      planItemId: entry.planItemId,
      verdict: commandResult.matched_expected_exit_code ? "pass" : "fail",
      observationEventIds: observation.appended_event_ids,
      actorType: "script",
      hostSurface,
      idempotencyKey: `${baseKey}:command-verdict:${stepId}`,
      recordedAt
    }).appended_event_ids);
  }

  for (const item of planResult.capsule.capsule.items) {
    const itemHasPending = pendingSteps.some((step) => step.use_case_id === item.use_case_id);
    const itemHasCommandVerdict = commandResults.some((result) => result.use_case_id === item.use_case_id);
    const itemHasFailure = commandResults.some((result) =>
      result.use_case_id === item.use_case_id && !result.matched_expected_exit_code
    );
    if (!itemHasPending && !itemHasCommandVerdict && !itemHasFailure) {
      const status = replayShowcaseRun({ context: options.context, runId });
      const planItem = status.items.find((candidate) => planResult.plan_result?.plan?.selected_items.some((selected) =>
        selected.plan_item_id === candidate.plan_item_id && selected.use_case_id === item.use_case_id
      ));
      if (planItem?.latest_observation_event_id) {
        eventsWritten.push(...appendShowcaseVerdict({
          context: options.context,
          runId,
          planItemId: planItem.plan_item_id,
          verdict: "pass",
          observationEventIds: [planItem.latest_observation_event_id],
          actorType,
          hostSurface,
          idempotencyKey: `${baseKey}:item-verdict:${item.use_case_id}`,
          recordedAt
        }).appended_event_ids);
      }
    }
  }

  let status = replayShowcaseRun({ context: options.context, runId });
  if (pendingSteps.length === 0 && status.unresolved_failure_count === 0) {
    const finish = finishShowcaseRun({
      context: options.context,
      runId,
      actorType,
      hostSurface,
      idempotencyKey: `${baseKey}:finish`,
      recordedAt
    });
    eventsWritten.push(...finish.appended_event_ids);
    status = finish.status;
  }
  const complete = pendingSteps.length === 0 &&
    status.execution_status === "completed" &&
    (status.run_outcome === "passed" || status.run_outcome === "passed_with_waivers");

  return {
    schema_version: 1,
    outcome: "performed",
    complete,
    capsule_id: options.capsuleId,
    run_id: runId,
    events_written: [...new Set(eventsWritten)],
    pending_steps: pendingSteps,
    command_results: commandResults,
    status,
    plan_result: planResult.plan_result,
    diagnostics: planResult.diagnostics
  };
}

function plannedCapsuleSteps(planResult: NonNullable<ReturnType<typeof planDemoCapsule>>):
  | PlannedCapsuleStep[]
  | { diagnostics: Diagnostic[] } {
  const plan = planResult.plan_result?.plan;
  const capsule = planResult.capsule?.capsule;
  if (!plan || !capsule) {
    return { diagnostics: [diagnostic("capsule.plan_missing", "Capsule plan is missing.", null)] };
  }
  const planItemByUseCase = new Map(plan.selected_items.map((item) => [item.use_case_id, item.plan_item_id]));
  const steps: PlannedCapsuleStep[] = [];
  const diagnostics: Diagnostic[] = [];
  capsule.items.forEach((item, itemIndex) => {
    const planItemId = planItemByUseCase.get(item.use_case_id);
    if (!planItemId) {
      diagnostics.push(diagnostic(
        "capsule.plan_item_missing",
        `Capsule use case '${item.use_case_id}' was not selected in the generated plan.`,
        null,
        item.use_case_id
      ));
      return;
    }
    item.runbook.forEach((step, stepIndex) => {
      steps.push({ itemIndex, stepIndex, useCaseId: item.use_case_id, planItemId, step });
    });
  });
  return diagnostics.length > 0 ? { diagnostics } : steps;
}

function resolveCommandSteps(
  options: DemoCapsuleRunOptions,
  commandSteps: Array<PlannedCapsuleStep & { step: DemoCapsuleCommandStep }>
): ResolvedCommandStep[] | { diagnostics: Diagnostic[] } {
  const diagnostics: Diagnostic[] = [];
  const workspaceRealPath = realpathSync(options.context.workspace_root);
  const resolved = commandSteps.map((entry) => {
    const requested = entry.step.working_directory || ".";
    const candidate = isAbsolute(requested)
      ? resolve(requested)
      : resolve(options.context.workspace_root, requested);
    const checked = existsSync(candidate) ? realpathSync(candidate) : candidate;
    const rel = relative(workspaceRealPath, checked);
    if (rel.startsWith("..") || isAbsolute(rel)) {
      diagnostics.push(diagnostic(
        "capsule.command_cwd_escape",
        "Command working_directory must stay inside repo.",
        null,
        entry.useCaseId
      ));
    }
    return { ...entry, cwd: checked };
  });
  return diagnostics.length > 0 ? { diagnostics } : resolved;
}

function runCommandStep(step: ResolvedCommandStep, timeoutMs: number): DemoCapsuleCommandResult {
  const result = spawnSync(step.step.executable, step.step.argv, {
    cwd: step.cwd,
    encoding: "utf8",
    env: commandEnvironment(),
    shell: false,
    timeout: timeoutMs,
    maxBuffer: COMMAND_MAX_BUFFER_BYTES
  });
  const exitCode = result.status;
  return {
    item_index: step.itemIndex,
    step_index: step.stepIndex,
    use_case_id: step.useCaseId,
    executable: step.step.executable,
    argv: step.step.argv,
    working_directory: step.step.working_directory,
    exit_code: exitCode,
    signal: result.signal,
    stdout: sanitizeCommandOutput(result.stdout ?? ""),
    stderr: sanitizeCommandOutput(result.stderr ?? result.error?.message ?? ""),
    expected_exit_codes: step.step.expected_exit_codes,
    matched_expected_exit_code: typeof exitCode === "number" && step.step.expected_exit_codes.includes(exitCode)
  };
}

function commandObservationText(result: DemoCapsuleCommandResult): string {
  return [
    `Command exited ${result.exit_code ?? "null"}${result.signal ? ` with signal ${result.signal}` : ""}.`,
    `Expected exit codes: ${result.expected_exit_codes.join(", ") || "<none>"}.`,
    `stdout:\n${result.stdout || "<empty>"}`,
    `stderr:\n${result.stderr || "<empty>"}`
  ].join("\n");
}

function blocked(
  capsuleId: string | null,
  planResult: DemoCapsuleRunResult["plan_result"],
  diagnostics: Diagnostic[]
): DemoCapsuleRunResult {
  return {
    schema_version: 1,
    outcome: "blocked",
    complete: false,
    capsule_id: capsuleId,
    run_id: null,
    events_written: [],
    pending_steps: [],
    command_results: [],
    status: null,
    plan_result: planResult,
    diagnostics
  };
}

function diagnostic(code: string, message: string, sourcePath: string | null, entityId: string | null = null): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: entityId,
    related_ids: []
  };
}

function stepKey(step: { itemIndex: number; stepIndex: number }): string {
  return `${step.itemIndex}:${step.stepIndex}`;
}

function hasCommittedEvent(context: DemoCapsuleRunOptions["context"], runId: string, idempotencyKey: string): boolean {
  return readShowcaseEvents(context, runId).events.some((event) => event.idempotency_key === idempotencyKey);
}

function commandEnvironment(): NodeJS.ProcessEnv {
  return copyDefinedEnv(["PATH", "HOME", "TMPDIR", "TEMP", "TMP", "SystemRoot", "WINDIR"]);
}

function copyDefinedEnv(keys: string[]): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const key of keys) {
    if (process.env[key] !== undefined) {
      env[key] = process.env[key];
    }
  }
  return env;
}

function sanitizeCommandOutput(value: string): string {
  return truncateOutput(redactSecrets(value));
}

function truncateOutput(value: string): string {
  return value.length > MAX_CAPTURED_OUTPUT_BYTES
    ? `${value.slice(0, MAX_CAPTURED_OUTPUT_BYTES)}\n[truncated]`
    : value;
}
