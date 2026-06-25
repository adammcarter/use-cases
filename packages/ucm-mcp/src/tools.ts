import { isAbsolute, relative, resolve } from "node:path";
import {
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  appendShowcaseFailureDecision,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  createCliResult,
  finishShowcaseRun,
  loadHostProfile,
  loadUseCaseMatrix,
  queryUseCases,
  readShowcaseEvents,
  replayEvidence,
  replayShowcaseRun,
  resolveWorkspaceContext,
  runHostDoctor,
  selectShowcasePlan,
  selectWalkthroughPlan,
  startShowcaseRun,
  toEvidenceAppendResult,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult,
  type CliResult,
  type Diagnostic,
  type HostName,
  type HostSurface,
  type ResolvedWorkspaceContext,
  type ShowcaseActorType,
  type ShowcaseAppendResult,
  type ShowcaseVerdict,
  type UseCaseQuery
} from "@presentation-skills/ucm-core";

type JsonObject = Record<string, unknown>;
type ToolMode = "read" | "write" | "approval_request";

export type McpToolDescriptor = {
  name: string;
  description: string;
  inputSchema: JsonObject;
  outputSchema: JsonObject;
  mutability: ToolMode;
  command: string;
};

type ToolDefinition = McpToolDescriptor & {
  handler: (args: JsonObject) => CliResult<unknown>;
};

const hostSurfaceDefault = "codex.cli" as HostSurface;

const toolInputBase = {
  type: "object",
  properties: {
    repo: { type: "string", description: "Repository/workspace root. Required for workspace-scoped tools." },
    data_root: { type: "string", description: "Optional data root, resolved relative to repo." },
    component: { type: "string" },
    timeout_ms: { type: "integer", minimum: 0 }
  },
  required: ["repo"],
  additionalProperties: true
};

const cliEnvelopeSchema = {
  type: "object",
  required: ["schema_version", "protocol_version", "command", "ok", "complete", "data", "diagnostics", "context"]
};

const toolDefinitions: ToolDefinition[] = [
  tool("doctor_roots", "doctor.roots", "Inspect resolved presentation-skills roots.", "read", toolInputBase, doctorRoots),
  tool("matrix_validate", "matrix.validate", "Validate use-case matrix files.", "read", toolInputBase, matrixValidate),
  tool("matrix_list", "matrix.list", "List and filter use cases.", "read", toolInputBase, matrixList),
  tool("matrix_status", "matrix.status", "Summarize matrix and evidence status.", "read", toolInputBase, matrixStatus),
  tool("evidence_status", "evidence.status", "Replay evidence status.", "read", toolInputBase, evidenceStatus),
  tool("evidence_record", "evidence.record", "Append an evidence record. Requires allow_write=true.", "write", toolInputBase, evidenceRecord),
  tool("evidence_void", "evidence.void", "Void an active evidence record. Requires allow_write=true.", "write", toolInputBase, evidenceVoid),
  tool("plan_showcase", "plan.showcase", "Generate a showcase plan.", "read", toolInputBase, (args) => planPresentation(args, "showcase")),
  tool("plan_walkthrough", "plan.walkthrough", "Generate a walkthrough plan.", "read", toolInputBase, (args) => planPresentation(args, "walkthrough")),
  tool("showcase_start", "showcase.start", "Start an ad hoc showcase run. Requires allow_write=true.", "write", toolInputBase, showcaseStart),
  tool("showcase_status", "showcase.status", "Replay showcase run status.", "read", toolInputBase, showcaseStatus),
  tool("showcase_record_observation", "showcase.record-observation", "Append a showcase observation. Requires allow_write=true.", "write", toolInputBase, showcaseObservation),
  tool("showcase_record_verdict", "showcase.record-verdict", "Append a showcase verdict. Requires allow_write=true.", "write", toolInputBase, showcaseVerdict),
  tool("showcase_decide", "showcase.decide", "Append a failure decision. Requires allow_write=true.", "write", toolInputBase, showcaseDecide),
  tool("showcase_finish", "showcase.finish", "Finish a showcase run. Requires allow_write=true.", "write", toolInputBase, showcaseFinish),
  tool(
    "showcase_request_approval",
    "showcase.request-approval",
    "Prepare CLI-mediated user approval instructions without appending approval.",
    "approval_request",
    toolInputBase,
    showcaseRequestApproval
  ),
  tool("host_doctor", "host.doctor", "Run read-only host profile/projection doctor checks.", "read", toolInputBase, hostDoctor)
];

export const mcpTools = toolDefinitions.map(({ handler: _handler, ...descriptor }) => descriptor);

export function callMcpTool(name: string, args: JsonObject): CliResult<unknown> {
  const definition = toolDefinitions.find((candidate) => candidate.name === name);
  if (!definition) {
    return errorEnvelope("mcp.unknown", "mcp.tool_unknown", `Unknown MCP tool '${name}'.`);
  }
  if (numberArg(args, "timeout_ms") === 0) {
    return errorEnvelope(definition.command, "mcp.timeout", "MCP tool call timed out before execution.");
  }
  if (definition.mutability === "write" && args.allow_write !== true) {
    return errorEnvelope(definition.command, "mcp.write_mode_required", "Write tools require allow_write=true.");
  }
  if (isTrustedUserClaim(args)) {
    return errorEnvelope(definition.command, "mcp.trusted_confirmation_required", "MCP cannot claim a trusted user actor without host confirmation.");
  }
  try {
    return definition.handler(args);
  } catch (error) {
    const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
    return errorEnvelope(definition.command, code, error instanceof Error ? error.message : String(error));
  }
}

function tool(
  name: string,
  command: string,
  description: string,
  mutability: ToolMode,
  inputSchema: JsonObject,
  handler: (args: JsonObject) => CliResult<unknown>
): ToolDefinition {
  return {
    name,
    command,
    description,
    inputSchema,
    outputSchema: cliEnvelopeSchema,
    mutability,
    handler
  };
}

function doctorRoots(args: JsonObject): CliResult<unknown> {
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

function matrixValidate(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "matrix.validate");
  if ("envelope" in context) return context.envelope;
  const snapshot = loadUseCaseMatrix({ context });
  return envelope("matrix.validate", toMatrixValidationResult(snapshot), context, {
    ok: true,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics
  });
}

function matrixList(args: JsonObject): CliResult<unknown> {
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

function matrixStatus(args: JsonObject): CliResult<unknown> {
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

function evidenceStatus(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "evidence.status");
  if ("envelope" in context) return context.envelope;
  const snapshot = replayEvidence({ context });
  return envelope("evidence.status", toEvidenceStatusResult(snapshot), context, {
    ok: snapshot.complete,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics
  });
}

function evidenceRecord(args: JsonObject): CliResult<unknown> {
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

function evidenceVoid(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "evidence.void");
  if ("envelope" in context) return context.envelope;
  const evidenceId = stringArg(args, "evidence");
  const expectedHead = stringArg(args, "expected_head");
  const reason = stringArg(args, "reason");
  if (!evidenceId || !expectedHead || !reason) {
    return errorEnvelope("evidence.void", "cli_invalid_arguments", "Missing evidence, expected_head, or reason.");
  }
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

function planPresentation(args: JsonObject, mode: "showcase" | "walkthrough"): CliResult<unknown> {
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

function showcaseStart(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.start");
  if ("envelope" in context) return context.envelope;
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
      generatedAt: stringArg(args, "generated_at") ?? "2026-06-25T12:00:00.000Z",
      freshnessEvaluatedAt: stringArg(args, "generated_at") ?? "2026-06-25T12:00:00.000Z"
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
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:00:00.000Z"
  }), context);
}

function showcaseStatus(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.status");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.status", "cli_invalid_arguments", "Missing run.");
  const status = replayShowcaseRun({ context, runId });
  return envelope("showcase.status", status, context, { complete: status.complete });
}

function showcaseObservation(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.record-observation");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const planItemId = stringArg(args, "item");
  const text = stringArg(args, "text");
  if (!runId || !planItemId || !text) {
    return errorEnvelope("showcase.record-observation", "cli_invalid_arguments", "Missing run, item, or text.");
  }
  return showcaseEnvelope("showcase.record-observation", appendShowcaseObservation({
    context,
    runId,
    planItemId,
    text,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:observation:${runId}:${planItemId}:${text}`,
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:01:00.000Z"
  }), context);
}

function showcaseVerdict(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.record-verdict");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const planItemId = stringArg(args, "item");
  const verdict = stringArg(args, "verdict");
  if (!runId || !planItemId || !verdict) {
    return errorEnvelope("showcase.record-verdict", "cli_invalid_arguments", "Missing run, item, or verdict.");
  }
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
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:02:00.000Z"
  }), context);
}

function showcaseDecide(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.decide");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  const verdictEventId = stringArg(args, "verdict_event");
  const decision = stringArg(args, "decision");
  const reason = stringArg(args, "reason");
  if (!runId || !verdictEventId || !decision || !reason) {
    return errorEnvelope("showcase.decide", "cli_invalid_arguments", "Missing run, verdict_event, decision, or reason.");
  }
  return showcaseEnvelope("showcase.decide", appendShowcaseFailureDecision({
    context,
    runId,
    verdictEventId,
    decision: decision as Parameters<typeof appendShowcaseFailureDecision>[0]["decision"],
    reason,
    actorType: actorArg(args),
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:decision:${runId}:${verdictEventId}:${decision}`,
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:02:30.000Z"
  }), context);
}

function showcaseFinish(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.finish");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.finish", "cli_invalid_arguments", "Missing run.");
  return showcaseEnvelope("showcase.finish", finishShowcaseRun({
    context,
    runId,
    actorType: "agent",
    hostSurface: hostSurfaceArg(args),
    idempotencyKey: stringArg(args, "idempotency_key") ?? `mcp:finish:${runId}`,
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:03:00.000Z"
  }), context);
}

function showcaseRequestApproval(args: JsonObject): CliResult<unknown> {
  const context = contextFromArgs(args, "showcase.request-approval");
  if ("envelope" in context) return context.envelope;
  const runId = stringArg(args, "run");
  if (!runId) return errorEnvelope("showcase.request-approval", "cli_invalid_arguments", "Missing run.");
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
      "presentation-skills",
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

function hostDoctor(args: JsonObject): CliResult<unknown> {
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

function errorEnvelope(command: string, code: string, message: string): CliResult<unknown> {
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

function isTrustedUserClaim(args: JsonObject): boolean {
  return stringArg(args, "actor_type") === "user" ||
    stringArg(args, "approver_type") === "user" ||
    stringArg(args, "trusted_confirmation") === "user";
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

function numberArg(args: JsonObject, name: string): number | null {
  const value = args[name];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function boolArg(args: JsonObject, name: string): boolean {
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
