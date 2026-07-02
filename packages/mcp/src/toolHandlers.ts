import { isAbsolute, relative, resolve } from "node:path";
import type {
  CliResult,
  Diagnostic,
  HostName,
  HostSurface,
  ResolvedWorkspaceContext,
  ShowcaseActorType,
  ShowcaseAppendResult,
  ShowcaseVerdict,
  UseCaseQuery
} from "@use-case-matrix/core";
import type { JsonObject } from "./toolSchemas.js";

type UcmCoreModule = typeof import("@use-case-matrix/core");

const {
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  isValidId,
  appendShowcaseFailureDecision,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  createCliResult,
  finishShowcaseRun,
  loadHostProfile,
  loadUseCaseMatrix,
  loadPresentationPlanFile,
  mutateUseCaseMatrix,
  queryUseCases,
  readShowcaseEvents,
  replayEvidence,
  replayShowcaseRun,
  resolveContainedPath,
  resolveWorkspaceContext,
  runDemoCapsule,
  runHostDoctor,
  selectShowcasePlan,
  selectWalkthroughPlan,
  startShowcaseRun,
  toEvidenceAppendResult,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult
} = await loadUcmCore();

async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@use-case-matrix/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../core/dist/index.js";
    return await import(bundledCoreSpecifier) as UcmCoreModule;
  }
}

function isMissingCorePackage(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ERR_MODULE_NOT_FOUND" && error.message.includes("@use-case-matrix/core");
}

const hostSurfaceDefault = "codex.cli" as HostSurface;

export function doctorRoots(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "doctor.roots");
  if ("envelope" in context) return context.envelope;
  return envelope("doctor.roots", {
    schema_version: 1,
    workspace_root: context.workspace_root,
    data_root: context.data_root,
    use_cases_root: context.use_cases_root,
    component_id: context.component_id,
    config_path: context.config_path,
    provenance: context.provenance
  }, context);
}

export function matrixValidate(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.validate");
  if ("envelope" in context) return context.envelope;
  const snapshot = loadUseCaseMatrix({ context });
  return envelope("matrix.validate", toMatrixValidationResult(snapshot), context, {
    ok: true,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics
  });
}

export function matrixList(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.list");
  if ("envelope" in context) return context.envelope;
  const snapshot = loadUseCaseMatrix({ context });
  const selected = queryUseCases(snapshot, {
    valueTiers: stringArrayArg(args, "value") as UseCaseQuery["valueTiers"],
    journeyRoles: stringArrayArg(args, "journey_role") as UseCaseQuery["journeyRoles"],
    lifecycles: stringArrayArg(args, "lifecycle") as UseCaseQuery["lifecycles"],
    hostSurfaces: stringArrayArg(args, "host") as UseCaseQuery["hostSurfaces"],
    tagsAny: stringArrayArg(args, "tag"),
    changedPaths: stringArrayArg(args, "changed_path")
  });
  const ok = boolArg(args, "strict") ? snapshot.complete : true;
  return envelope("matrix.list", toMatrixListResult(snapshot, selected), context, {
    ok,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics
  });
}

export function matrixStatus(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.status");
  if ("envelope" in context) return context.envelope;
  const matrix = loadUseCaseMatrix({ context });
  const evidence = replayEvidence({ context });
  const data = {
    schema_version: 1,
    complete: matrix.complete && evidence.complete,
    matrix: toMatrixValidationResult(matrix),
    evidence: toEvidenceStatusResult(evidence)
  };
  return envelope("matrix.status", data, context, {
    ok: data.complete,
    complete: data.complete,
    diagnostics: [...matrix.diagnostics, ...evidence.diagnostics]
  });
}

export function useCaseUpsert(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.upsert");
  if ("envelope" in context) return context.envelope;
  const targetFile = stringArg(args, "file");
  const useCase = objectArg(args, "use_case");
  if (!targetFile || !useCase) {
    return errorEnvelope("matrix.upsert", "cli_invalid_arguments", "Missing file or use_case.");
  }
  const result = mutateUseCaseMatrix({
    context,
    operation: "upsert",
    targetFile,
    useCase,
    expectedSemanticHash: stringArg(args, "expected_hash") ?? undefined,
    actor: actorArg(args)
  });
  return useCaseMutationEnvelope("matrix.upsert", result, context);
}

export function useCaseRemove(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.remove");
  if ("envelope" in context) return context.envelope;
  const useCaseId = stringArg(args, "use_case");
  const reason = stringArg(args, "reason");
  if (!useCaseId || !reason) {
    return errorEnvelope("matrix.remove", "cli_invalid_arguments", "Missing use_case or reason.");
  }
  const result = mutateUseCaseMatrix({
    context,
    operation: "remove",
    useCaseId,
    reason,
    expectedSemanticHash: stringArg(args, "expected_hash") ?? undefined,
    actor: actorArg(args)
  });
  return useCaseMutationEnvelope("matrix.remove", result, context);
}

export function evidenceStatus(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "evidence.status");
  if ("envelope" in context) return context.envelope;
  const snapshot = replayEvidence({ context });
  return envelope("evidence.status", toEvidenceStatusResult(snapshot), context, {
    ok: snapshot.complete,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics
  });
}

export function evidenceRecord(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "evidence.record");
  if ("envelope" in context) return context.envelope;
  const useCaseId = stringArg(args, "use_case");
  if (!useCaseId) return errorEnvelope("evidence.record", "evidence.use_case.required", "Missing use_case.");
  const matrix = loadUseCaseMatrix({ context });
  const resolved = matrix.resolveUseCase(useCaseId);
  if (resolved.kind !== "resolved") {
    return errorEnvelope("evidence.record", "evidence.use_case.unresolved", `Use case '${useCaseId}' is ${resolved.kind}.`);
  }
  const kind = stringArg(args, "kind") ?? "manual_observation";
  const result = stringArg(args, "result") ?? "observed";
  const append = appendEvidenceEvent({
    context,
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:${useCaseId}:${kind}:${result}`,
    target: {
      use_case_id: useCaseId,
      use_case_semantic_hash: resolved.useCase.semanticHash
    },
    kind: kind as Parameters<typeof appendEvidenceEvent>[0]["kind"],
    result: result as Parameters<typeof appendEvidenceEvent>[0]["result"],
    summary: stringArg(args, "summary") ?? `Recorded ${kind} evidence for ${useCaseId}.`,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args)
  });
  return envelope("evidence.record", toEvidenceAppendResult(append), context);
}

export function evidenceVoid(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "evidence.void");
  if ("envelope" in context) return context.envelope;
  const evidenceId = stringArg(args, "evidence");
  const expectedHead = stringArg(args, "expected_head");
  const reason = stringArg(args, "reason");
  if (!evidenceId || !expectedHead || !reason) {
    return errorEnvelope("evidence.void", "cli_invalid_arguments", "Missing evidence, expected_head, or reason.");
  }
  const invalidEvidenceId = rejectUnsafeId("evidence.void", "evidence", evidenceId);
  if (invalidEvidenceId) return invalidEvidenceId;
  const append = appendEvidenceVoidEvent({
    context,
    evidenceId,
    expectedHeadEventId: expectedHead,
    reason,
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:void:${evidenceId}:${expectedHead}`,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args)
  });
  return envelope("evidence.void", toEvidenceAppendResult(append), context);
}

export function planPresentation(args: JsonObject, mode: "showcase" | "walkthrough"): CliResult<unknown> {
  const command = `plan.${mode}`;
  const context = contextFromArgs(args, command);
  if ("envelope" in context) return context.envelope;
  const matrix = loadUseCaseMatrix({ context });
  const evidence = replayEvidence({ context });
  const request = {
    audience: stringArg(args, "audience") ?? "reviewer",
    timeboxSeconds: numberArg(args, "timebox_seconds") ?? (mode === "showcase" ? 600 : 1800),
    maxItems: numberArg(args, "max_items") ?? undefined,
    hostSurface: (stringArg(args, "host") ?? "unknown") as Parameters<typeof selectShowcasePlan>[0]["request"]["hostSurface"],
    changedPaths: stringArrayArg(args, "changed_path"),
    generatedAt: stringArg(args, "generated_at") ?? undefined,
    strict: boolArg(args, "strict")
  };
  const result = mode === "showcase"
    ? selectShowcasePlan({ context, matrix, evidence, request })
    : selectWalkthroughPlan({ context, matrix, evidence, request });
  return envelope(command, result, context, {
    ok: result.outcome !== "integrity_blocked",
    complete: result.plan?.complete ?? (result.outcome === "no_eligible_items" && matrix.complete && evidence.complete),
    diagnostics: [...matrix.diagnostics, ...evidence.diagnostics]
  });
}

export function capsuleRun(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "capsule.run");
  if ("envelope" in context) return context.envelope;
  const capsuleId = stringArg(args, "capsule");
  if (!capsuleId) {
    return errorEnvelope("capsule.run", "cli_invalid_arguments", "Missing capsule.");
  }
  const result = runDemoCapsule({
    context,
    capsuleId,
    executeCommands: boolArg(args, "execute_commands"),
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? undefined,
    recordedAt: stringArg(args, "recorded_at") ?? undefined,
    commandTimeoutMs: numberArg(args, "command_timeout_ms") ?? undefined
  });
  return envelope("capsule.run", result, context, {
    ok: result.outcome !== "blocked",
    complete: result.complete,
    diagnostics: result.diagnostics
  });
}

export function showcaseStart(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.start");
  if ("envelope" in context) return context.envelope;
  const planFile = stringArg(args, "plan_file");
  if (planFile) {
    const contained = containedFilePath("showcase.start", context.workspace_root, planFile);
    if ("envelope" in contained) return contained.envelope;
    const plan = loadPresentationPlanFile(contained.path);
    return showcaseEnvelope("showcase.start", startShowcaseRun({
      context,
      plan,
      controlMode: "agent_led",
      actorType: actorArg(args),
      hostSurface: hostSurfaceArg(args),
      idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:start-plan:${plan.plan_content_hash}`,
      recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
    }), context);
  }
  const selected = stringArg(args, "select");
  if (!selected) return errorEnvelope("showcase.start", "showcase.plan_required", "Only ad hoc select starts are supported.");
  const matrix = loadUseCaseMatrix({ context });
  const evidence = replayEvidence({ context });
  const planResult = selectShowcasePlan({
    context,
    matrix,
    evidence,
    request: {
      audience: stringArg(args, "audience") ?? "reviewer",
      timeboxSeconds: numberArg(args, "timebox_seconds") ?? 600,
      maxItems: 1,
      hostSurface: hostSurfaceArg(args),
      requestedUseCaseIds: [selected],
      generatedAt: stringArg(args, "generated_at") ?? new Date().toISOString(),
      freshnessEvaluatedAt: stringArg(args, "generated_at") ?? new Date().toISOString()
    }
  });
  if (!planResult.plan || !planResult.plan.selected_items.some((item) => item.use_case_id === selected)) {
    return errorEnvelope("showcase.start", "showcase.selected_use_case_unavailable", "Selected use case was not available for an ad hoc plan.");
  }
  return showcaseEnvelope("showcase.start", startShowcaseRun({
    context,
    plan: planResult.plan,
    controlMode: "agent_led",
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:start:${selected}`,
    recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
  }), context);
}

export function showcaseStatus(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.status");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.status", "cli_invalid_arguments", "Missing run.");
  const invalidStatusId = rejectUnsafeId("showcase.status", "run", runId);
  if (invalidStatusId) return invalidStatusId;
  const status = replayShowcaseRun({ context, runId });
  return envelope("showcase.status", status, context, { complete: status.complete });
}

export function showcaseObservation(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.record-observation");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const planItemId = stringArg(args, "item");
  const text = stringArg(args, "text");
  if (!runId || !planItemId || !text) {
    return errorEnvelope("showcase.record-observation", "cli_invalid_arguments", "Missing run, item, or text.");
  }
  const invalidObservationId =
    rejectUnsafeId("showcase.record-observation", "run", runId) ??
    rejectUnsafeId("showcase.record-observation", "item", planItemId);
  if (invalidObservationId) return invalidObservationId;
  return showcaseEnvelope("showcase.record-observation", appendShowcaseObservation({
    context,
    runId,
    planItemId,
    text,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:observation:${runId}:${planItemId}:${text}`,
    recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
  }), context);
}

export function showcaseVerdict(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.record-verdict");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const planItemId = stringArg(args, "item");
  const verdict = stringArg(args, "verdict");
  if (!runId || !planItemId || !verdict) {
    return errorEnvelope("showcase.record-verdict", "cli_invalid_arguments", "Missing run, item, or verdict.");
  }
  const invalidVerdictId =
    rejectUnsafeId("showcase.record-verdict", "run", runId) ??
    rejectUnsafeId("showcase.record-verdict", "item", planItemId);
  if (invalidVerdictId) return invalidVerdictId;
  const status = replayShowcaseRun({ context, runId });
  const item = status.items.find((candidate) => candidate.plan_item_id === planItemId);
  if (!item?.latest_observation_event_id) {
    return errorEnvelope("showcase.record-verdict", "showcase.verdict_requires_observation", "Verdict requires a prior observation.");
  }
  return showcaseEnvelope("showcase.record-verdict", appendShowcaseVerdict({
    context,
    runId,
    planItemId,
    verdict: verdict as ShowcaseVerdict,
    observationEventIds: [item.latest_observation_event_id],
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:verdict:${runId}:${planItemId}:${verdict}`,
    recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
  }), context);
}

export function showcaseDecide(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.decide");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const verdictEventId = stringArg(args, "verdict_event");
  const decision = stringArg(args, "decision");
  const reason = stringArg(args, "reason");
  if (!runId || !verdictEventId || !decision || !reason) {
    return errorEnvelope("showcase.decide", "cli_invalid_arguments", "Missing run, verdict_event, decision, or reason.");
  }
  const invalidDecideId = rejectUnsafeId("showcase.decide", "run", runId);
  if (invalidDecideId) return invalidDecideId;
  return showcaseEnvelope("showcase.decide", appendShowcaseFailureDecision({
    context,
    runId,
    verdictEventId,
    decision: decision as Parameters<typeof appendShowcaseFailureDecision>[0]["decision"],
    reason,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:decision:${runId}:${verdictEventId}:${decision}`,
    recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
  }), context);
}

export function showcaseFinish(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.finish");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.finish", "cli_invalid_arguments", "Missing run.");
  const invalidFinishId = rejectUnsafeId("showcase.finish", "run", runId);
  if (invalidFinishId) return invalidFinishId;
  return showcaseEnvelope("showcase.finish", finishShowcaseRun({
    context,
    runId,
    actorType: "agent",
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:finish:${runId}`,
    recordedAt: stringArg(args, "recorded_at") ?? new Date().toISOString()
  }), context);
}

export function showcaseRequestApproval(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.request-approval");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.request-approval", "cli_invalid_arguments", "Missing run.");
  const invalidApprovalId = rejectUnsafeId("showcase.request-approval", "run", runId);
  if (invalidApprovalId) return invalidApprovalId;
  const status = replayShowcaseRun({ context, runId });
  const events = readShowcaseEvents(context, runId).events;
  const start = events.find((event) => event.event_type === "run_started");
  const finish = events.slice().reverse().find((event) => event.event_type === "run_finished");
  const plan = start?.payload.plan as { plan_content_hash?: string } | undefined;
  return envelope("showcase.request-approval", {
    schema_version: 1,
    decision_required: true,
    trusted_confirmation_required: true,
    run_id: runId,
    plan_hash: plan?.plan_content_hash ?? null,
    finish_event_id: finish?.event_id ?? null,
    known_gaps: status.known_gaps,
    suggested_cli_command: [
      "ucm",
      "showcase",
      "approve",
      "--run",
      runId,
      "--statement",
      stringArg(args, "statement") ?? "<user approval statement>",
      "--json"
    ],
    status
  }, context, { complete: status.complete });
}

export function hostDoctor(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "host.doctor");
  if ("envelope" in context) return context.envelope;
  const host = stringArg(args, "host") as HostName | null;
  if (!host) return errorEnvelope("host.doctor", "host.required", "Missing host.");
  const profile = loadHostProfile({ pluginRoot: context.plugin_root, host });
  if (!profile.profile) {
    return errorEnvelope("host.doctor", "host.profile_unavailable", profile.diagnostics[0]?.message ?? "Host profile unavailable.");
  }
  return envelope("host.doctor", runHostDoctor({ context, profile: profile.profile }), context);
}

function showcaseEnvelope(command: string, result: ShowcaseAppendResult, context: ResolvedWorkspaceContext): CliResult<unknown> {
  return envelope(command, result, context, { complete: result.status.complete });
}

function useCaseMutationEnvelope(
  command: string,
  result: ReturnType<typeof mutateUseCaseMatrix>,
  context: ResolvedWorkspaceContext
): CliResult<unknown> {
  const ok = result.status !== "blocked";
  return envelope(command, result, context, {
    ok,
    complete: ok,
    diagnostics: result.diagnostics
  });
}

function envelope(
  command: string,
  data: unknown,
  context: ResolvedWorkspaceContext,
  options: { ok?: boolean; complete?: boolean; diagnostics?: Diagnostic[] } = {}
): CliResult<unknown> {
  return createCliResult(command, data, {
    ok: options.ok ?? true,
    complete: options.complete ?? true,
    diagnostics: options.diagnostics ?? [],
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
}

function contextFromArgs(args: JsonObject, command: string): ResolvedWorkspaceContext | { envelope: CliResult<unknown> } {
  const repo = stringArg(args, "repo");
  if (!repo) {
    return { envelope: errorEnvelope(command, "mcp.repo_required", "MCP workspace tools require repo.") };
  }
  const workspaceRoot = resolve(process.cwd(), repo);
  const dataRootValue = stringArg(args, "data_root");
  const dataRoot = dataRootValue ? resolve(workspaceRoot, dataRootValue) : undefined;
  if (dataRoot) {
    const rel = relative(workspaceRoot, dataRoot);
    if (rel === ".." || rel.startsWith("../") || isAbsolute(rel)) {
      return { envelope: errorEnvelope(command, "unsafe_data_root", "data_root must stay inside repo.") };
    }
  }
  return resolveWorkspaceContext({
    workspaceRoot,
    dataRootOverride: dataRoot,
    component: stringArg(args, "component") ?? undefined
  });
}

export function errorEnvelope(command: string, code: string, message: string): CliResult<unknown> {
  return createCliResult(command, {}, {
    ok: false,
    complete: false,
    diagnostics: [{
      code,
      severity: "error",
      message,
      source_path: null,
      json_pointer: null,
      entity_id: null,
      related_ids: []
    }]
  });
}

// SECURITY: reject a user-supplied id that is not a canonical id before it can
// become a filesystem path segment or a ledger lookup key. Returns the stable
// UCM_INVALID_ID envelope on failure, or null when the value is safe.
function rejectUnsafeId(command: string, paramName: string, value: string): CliResult<unknown> | null {
  return isValidId(value)
    ? null
    : errorEnvelope(
        command,
        "UCM_INVALID_ID",
        `Invalid ${paramName} '${value}': must be a canonical id (lowercase, no path separators, no '..').`
      );
}

// SECURITY: bound a user-supplied file path (e.g. plan_file) to the workspace,
// symlink-safe, BEFORE it is read from disk. Returns the safe absolute path, or the
// stable UCM_PATH_ESCAPE envelope on escape.
function containedFilePath(
  command: string,
  workspaceRoot: string,
  candidate: string
): { path: string } | { envelope: CliResult<unknown> } {
  try {
    return { path: resolveContainedPath(workspaceRoot, candidate) };
  } catch (error) {
    if (error instanceof Error && "code" in error && (error as { code?: unknown }).code === "path.escape") {
      return { envelope: errorEnvelope(command, "UCM_PATH_ESCAPE", error.message) };
    }
    throw error;
  }
}

export function isTrustedUserClaim(args: JsonObject): boolean {
  return stringArg(args, "actor_type") === "user" ||
    stringArg(args, "approver_type") === "user" ||
    stringArg(args, "trusted_confirmation") === "user";
}

export function mcpServerWriteModeEnabled(): boolean {
  return process.env.UCM_MCP_WRITE === "1";
}

export function mcpServerCommandExecutionEnabled(): boolean {
  return process.env.UCM_MCP_COMMAND_EXECUTION === "1";
}

function actorArg(args: JsonObject): Exclude<ShowcaseActorType, "user"> {
  const actor = stringArg(args, "actor_type");
  return actor === "script" || actor === "system" ? actor : "agent";
}

function hostSurfaceArg(args: JsonObject): HostSurface {
  return (stringArg(args, "host_surface") ?? hostSurfaceDefault) as HostSurface;
}

function stringArg(args: JsonObject, name: string): string | null {
  const value = args[name];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function objectArg(args: JsonObject, name: string): Record<string, unknown> | null {
  const value = args[name];
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

export function numberArg(args: JsonObject, name: string): number | null {
  const value = args[name];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export function boolArg(args: JsonObject, name: string): boolean {
  return args[name] === true;
}

function stringArrayArg(args: JsonObject, name: string): string[] {
  const value = args[name];
  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === "string");
  }
  if (typeof value === "string") {
    return [value];
  }
  return [];
}
