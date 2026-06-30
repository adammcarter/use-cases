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
} from "@use-cases-plugin/core";

type UcmCoreModule = typeof import("@use-cases-plugin/core");

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
    return await import("@use-cases-plugin/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../core/dist/index.js";
    return await import(bundledCoreSpecifier) as UcmCoreModule;
  }
}

function isMissingCorePackage(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ERR_MODULE_NOT_FOUND" && error.message.includes("@use-cases-plugin/core");
}

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

// Closed value-domains mirrored from @use-cases-plugin/core so the advertised MCP
// schemas document exactly what each parameter accepts. These are advisory: the
// server does not validate inbound args against the schema (handlers self-validate
// and still forward every undeclared field to the CLI), so declaring them only
// improves self-documentation — it never narrows the CLI-parity passthrough.
const HOST_SURFACES = [
  "claude.cli",
  "claude.desktop",
  "codex.cli",
  "copilot.cli",
  "copilot.github",
  "opencode.cli",
  "unknown"
] as const;
const HOST_NAMES = ["claude", "codex", "copilot", "opencode"] as const;
const ACTOR_TYPES = ["agent", "script", "system"] as const;
const VERDICTS = ["pass", "partial", "fail", "waived", "blocked"] as const;
const FAILURE_DECISIONS = ["continue", "pause_to_fix", "waive_with_reason", "abort"] as const;
const EVIDENCE_KINDS = [
  "manual_observation",
  "agent_observation",
  "command_result",
  "test_result",
  "live_demo",
  "artifact_review",
  "host_conformance",
  "url"
] as const;
const EVIDENCE_RESULTS = ["pass", "fail", "inconclusive", "observed"] as const;
const VALUE_TIERS = ["critical", "core", "supporting", "long_tail"] as const;
const JOURNEY_ROLES = ["golden", "alternate", "edge", "negative", "failure"] as const;
const LIFECYCLES = ["planned", "active", "deprecated", "removed"] as const;
const USAGE_FREQUENCIES = ["common", "occasional", "rare"] as const;

// Shared property fragments reused across tool schemas.
const repoProp = { type: "string", description: "Repository/workspace root. Required for workspace-scoped tools." };
const dataRootProp = { type: "string", description: "Optional data root, resolved relative to repo (must stay inside repo)." };
const componentProp = { type: "string", description: "Optional component id used to scope resolution within the workspace." };
const timeoutProp = {
  type: "integer",
  minimum: 0,
  description: "Advisory call budget in milliseconds; 0 aborts the call before any execution."
};
const allowWriteProp = {
  type: "boolean",
  description: "Must be true for any ledger mutation. Write tools also require the server to run in write mode (UCP_MCP_WRITE=1)."
};
const actorTypeProp = {
  type: "string",
  enum: ACTOR_TYPES,
  description: "Non-user actor recording the event (defaults to agent). 'user' is rejected over MCP; trusted-user approval is CLI-mediated."
};
const hostSurfaceProp = {
  type: "string",
  enum: HOST_SURFACES,
  description: "Originating host surface recorded on the event (defaults to codex.cli)."
};
const idempotencyKeyProp = {
  type: "string",
  description: "Caller-supplied idempotency key; a deterministic key is derived when omitted."
};
const recordedAtProp = { type: "string", description: "ISO-8601 timestamp override for the appended event." };
const runProp = { type: "string", description: "Showcase run id." };
const planItemProp = { type: "string", description: "Plan item id within the showcase run." };
const expectedHashProp = { type: "string", description: "Expected semantic hash for optimistic-concurrency guarding of the matrix file." };

const useCaseObjectProp = {
  type: "object",
  description: "Full use-case entry (UseCaseV1 shape) to add or replace at its id.",
  properties: {
    id: { type: "string", description: "Canonical use-case id (e.g. 'auth.login')." },
    title: { type: "string", description: "Human-readable title." },
    lifecycle: { type: "string", enum: LIFECYCLES, description: "Lifecycle state." },
    value_tier: { type: "string", enum: VALUE_TIERS, description: "Business value tier." },
    journey_role: { type: "string", enum: JOURNEY_ROLES, description: "Role of this case within the user journey." },
    usage_frequency: { type: "string", enum: USAGE_FREQUENCIES, description: "How often the case is exercised." },
    tags: { type: "array", items: { type: "string" }, description: "Free-form tags." }
  },
  required: ["id"],
  additionalProperties: true
};

// Build a workspace-scoped input schema: always carries repo/data_root/component/
// timeout_ms, keeps repo required, and leaves additionalProperties open for
// CLI-parity passthrough.
function workspaceSchema(properties: JsonObject = {}, required: string[] = []): JsonObject {
  return {
    type: "object",
    properties: {
      repo: repoProp,
      data_root: dataRootProp,
      component: componentProp,
      timeout_ms: timeoutProp,
      ...properties
    },
    required: ["repo", ...required],
    additionalProperties: true
  };
}

const toolInputBase = workspaceSchema();

const matrixListInputSchema = workspaceSchema({
  value: { type: "array", items: { type: "string", enum: VALUE_TIERS }, description: "Filter to these value tiers." },
  journey_role: { type: "array", items: { type: "string", enum: JOURNEY_ROLES }, description: "Filter to these journey roles." },
  lifecycle: { type: "array", items: { type: "string", enum: LIFECYCLES }, description: "Filter to these lifecycle states." },
  host: { type: "array", items: { type: "string", enum: HOST_SURFACES }, description: "Filter to use cases applicable to these host surfaces." },
  tag: { type: "array", items: { type: "string" }, description: "Filter to use cases carrying any of these tags." },
  changed_path: { type: "array", items: { type: "string" }, description: "Filter to use cases impacted by these changed paths." },
  strict: { type: "boolean", description: "Report ok=false when the matrix is incomplete." }
});

//: @use-case: mcp.surface.declared_tool_schemas
const useCaseUpsertInputSchema = workspaceSchema({
  file: { type: "string", description: "Workspace-relative matrix file the entry is written into." },
  use_case: useCaseObjectProp,
  expected_hash: expectedHashProp,
  actor_type: actorTypeProp,
  allow_write: allowWriteProp
}, ["file", "use_case"]);
//: @use-case: end mcp.surface.declared_tool_schemas

const useCaseRemoveInputSchema = workspaceSchema({
  use_case: { type: "string", description: "Canonical use-case id to mark removed." },
  reason: { type: "string", description: "Why the use case is being removed." },
  expected_hash: expectedHashProp,
  actor_type: actorTypeProp,
  allow_write: allowWriteProp
}, ["use_case", "reason"]);

const evidenceRecordInputSchema = workspaceSchema({
  use_case: { type: "string", description: "Canonical use-case id the evidence attaches to." },
  kind: { type: "string", enum: EVIDENCE_KINDS, description: "Evidence kind (defaults to manual_observation)." },
  result: { type: "string", enum: EVIDENCE_RESULTS, description: "Observed result (defaults to observed)." },
  summary: { type: "string", description: "Human-readable summary of what was observed." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  allow_write: allowWriteProp
}, ["use_case"]);

const evidenceVoidInputSchema = workspaceSchema({
  evidence: { type: "string", description: "Canonical evidence id to void." },
  expected_head: { type: "string", description: "Expected head event id (optimistic-concurrency guard)." },
  reason: { type: "string", description: "Why the evidence is being voided." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  allow_write: allowWriteProp
}, ["evidence", "expected_head", "reason"]);

const planInputSchema = workspaceSchema({
  audience: { type: "string", description: "Intended audience label for the plan (default 'reviewer')." },
  timebox_seconds: { type: "integer", minimum: 0, description: "Total presentation budget in seconds (default 600 showcase / 1800 walkthrough)." },
  max_items: { type: "integer", minimum: 1, description: "Cap on the number of selected items." },
  host: { type: "string", enum: HOST_SURFACES, description: "Host surface to plan for (default 'unknown')." },
  changed_path: { type: "array", items: { type: "string" }, description: "Changed paths to bias selection toward impacted use cases." },
  generated_at: { type: "string", description: "ISO-8601 generation timestamp override." },
  strict: { type: "boolean", description: "Block the plan when the matrix or evidence is incomplete." }
});

const capsuleRunInputSchema = workspaceSchema({
  capsule: { type: "string", description: "Demo capsule id to run." },
  execute_commands: { type: "boolean", description: "Execute capsule commands (requires UCP_MCP_COMMAND_EXECUTION=1)." },
  command_timeout_ms: { type: "integer", minimum: 0, description: "Per-command execution timeout in milliseconds." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["capsule"]);

const showcaseStartInputSchema = workspaceSchema({
  select: { type: "string", description: "Use-case id to build an ad hoc single-item plan for (alternative to plan_file)." },
  plan_file: { type: "string", description: "Workspace-relative presentation-plan JSON file to start from (alternative to select)." },
  audience: { type: "string", description: "Audience label for an ad hoc plan (default 'reviewer')." },
  timebox_seconds: { type: "integer", minimum: 0, description: "Timebox in seconds for an ad hoc plan (default 600)." },
  generated_at: { type: "string", description: "ISO-8601 plan generation timestamp override." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
});

const showcaseStatusInputSchema = workspaceSchema({ run: runProp }, ["run"]);

const showcaseObservationInputSchema = workspaceSchema({
  run: runProp,
  item: planItemProp,
  text: { type: "string", description: "Observation text for the plan item." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run", "item", "text"]);

const showcaseVerdictInputSchema = workspaceSchema({
  run: runProp,
  item: planItemProp,
  verdict: { type: "string", enum: VERDICTS, description: "Verdict for the plan item; requires a prior observation." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run", "item", "verdict"]);

const showcaseDecideInputSchema = workspaceSchema({
  run: runProp,
  verdict_event: { type: "string", description: "Verdict event id the failure decision applies to." },
  decision: { type: "string", enum: FAILURE_DECISIONS, description: "Disposition for a failing/partial item." },
  reason: { type: "string", description: "Why this decision was taken." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run", "verdict_event", "decision", "reason"]);

const showcaseFinishInputSchema = workspaceSchema({
  run: runProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run"]);

const showcaseRequestApprovalInputSchema = workspaceSchema({
  run: runProp,
  statement: { type: "string", description: "Draft approval statement echoed into the suggested CLI command." }
}, ["run"]);

const hostDoctorInputSchema = workspaceSchema({
  host: { type: "string", enum: HOST_NAMES, description: "Host whose profile/projection is checked." }
}, ["host"]);

const cliEnvelopeSchema = {
  type: "object",
  required: ["schema_version", "protocol_version", "command", "ok", "complete", "data", "diagnostics", "context"]
};

const toolDefinitions: ToolDefinition[] = [
  tool("doctor_roots", "doctor.roots", "Inspect resolved use-cases-plugin roots.", "read", toolInputBase, doctorRoots),
  tool("matrix_validate", "matrix.validate", "Validate use-case matrix files.", "read", toolInputBase, matrixValidate),
  tool("matrix_list", "matrix.list", "List and filter use cases.", "read", matrixListInputSchema, matrixList),
  tool("matrix_status", "matrix.status", "Summarize matrix and evidence status.", "read", toolInputBase, matrixStatus),
  tool("use_case_upsert", "matrix.upsert", "Add or update one use-case entry. Requires allow_write=true.", "write", useCaseUpsertInputSchema, useCaseUpsert),
  tool("use_case_remove", "matrix.remove", "Mark one use case removed. Requires allow_write=true.", "write", useCaseRemoveInputSchema, useCaseRemove),
  tool("evidence_status", "evidence.status", "Replay evidence status.", "read", toolInputBase, evidenceStatus),
  tool("evidence_record", "evidence.record", "Append an evidence record. Requires allow_write=true.", "write", evidenceRecordInputSchema, evidenceRecord),
  tool("evidence_void", "evidence.void", "Void an active evidence record. Requires allow_write=true.", "write", evidenceVoidInputSchema, evidenceVoid),
  tool("plan_showcase", "plan.showcase", "Generate a showcase plan.", "read", planInputSchema, (args) => planPresentation(args, "showcase")),
  tool("plan_walkthrough", "plan.walkthrough", "Generate a walkthrough plan.", "read", planInputSchema, (args) => planPresentation(args, "walkthrough")),
  tool("capsule_run", "capsule.run", "Run a persisted demo capsule. Requires allow_write=true.", "write", capsuleRunInputSchema, capsuleRun),
  tool("showcase_start", "showcase.start", "Start an ad hoc showcase run. Requires allow_write=true.", "write", showcaseStartInputSchema, showcaseStart),
  tool("showcase_status", "showcase.status", "Replay showcase run status.", "read", showcaseStatusInputSchema, showcaseStatus),
  tool("showcase_record_observation", "showcase.record-observation", "Append a showcase observation. Requires allow_write=true.", "write", showcaseObservationInputSchema, showcaseObservation),
  tool("showcase_record_verdict", "showcase.record-verdict", "Append a showcase verdict. Requires allow_write=true.", "write", showcaseVerdictInputSchema, showcaseVerdict),
  tool("showcase_decide", "showcase.decide", "Append a failure decision. Requires allow_write=true.", "write", showcaseDecideInputSchema, showcaseDecide),
  tool("showcase_finish", "showcase.finish", "Finish a showcase run. Requires allow_write=true.", "write", showcaseFinishInputSchema, showcaseFinish),
  tool(
    "showcase_request_approval",
    "showcase.request-approval",
    "Prepare CLI-mediated user approval instructions without appending approval.",
    "approval_request",
    showcaseRequestApprovalInputSchema,
    showcaseRequestApproval
  ),
  tool("host_doctor", "host.doctor", "Run read-only host profile/projection doctor checks.", "read", hostDoctorInputSchema, hostDoctor)
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
  if (definition.mutability === "write" && !mcpServerWriteModeEnabled()) {
    return errorEnvelope(definition.command, "mcp.server_write_mode_required", "MCP server was not started with write mode enabled.");
  }
  if (definition.name === "capsule_run" && boolArg(args, "execute_commands") && !mcpServerCommandExecutionEnabled()) {
    return errorEnvelope(
      definition.command,
      "mcp.server_command_execution_mode_required",
      "MCP server was not started with command execution enabled."
    );
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

function useCaseUpsert(args: JsonObject): CliResult<unknown> {
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

function useCaseRemove(args: JsonObject): CliResult<unknown> {
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

function capsuleRun(args: JsonObject): CliResult<unknown> {
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

function showcaseStart(args: JsonObject): CliResult<unknown> {
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
      recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:00:00.000Z"
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
  const invalidStatusId = rejectUnsafeId("showcase.status", "run", runId);
  if (invalidStatusId) return invalidStatusId;
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
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:02:30.000Z"
  }), context);
}

function showcaseFinish(args: JsonObject): CliResult<unknown> {
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
    recordedAt: stringArg(args, "recorded_at") ?? "2026-06-25T12:03:00.000Z"
  }), context);
}

function showcaseRequestApproval(args: JsonObject): CliResult<unknown> {
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
      "ucp",
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

// SECURITY: reject a user-supplied id that is not a canonical id before it can
// become a filesystem path segment or a ledger lookup key. Returns the stable
// UCP_INVALID_ID envelope on failure, or null when the value is safe.
function rejectUnsafeId(command: string, paramName: string, value: string): CliResult<unknown> | null {
  return isValidId(value)
    ? null
    : errorEnvelope(
        command,
        "UCP_INVALID_ID",
        `Invalid ${paramName} '${value}': must be a canonical id (lowercase, no path separators, no '..').`
      );
}

// SECURITY: bound a user-supplied file path (e.g. plan_file) to the workspace,
// symlink-safe, BEFORE it is read from disk. Returns the safe absolute path, or the
// stable UCP_PATH_ESCAPE envelope on escape.
function containedFilePath(
  command: string,
  workspaceRoot: string,
  candidate: string
): { path: string } | { envelope: CliResult<unknown> } {
  try {
    return { path: resolveContainedPath(workspaceRoot, candidate) };
  } catch (error) {
    if (error instanceof Error && "code" in error && (error as { code?: unknown }).code === "path.escape") {
      return { envelope: errorEnvelope(command, "UCP_PATH_ESCAPE", error.message) };
    }
    throw error;
  }
}

function isTrustedUserClaim(args: JsonObject): boolean {
  return stringArg(args, "actor_type") === "user" ||
    stringArg(args, "approver_type") === "user" ||
    stringArg(args, "trusted_confirmation") === "user";
}

function mcpServerWriteModeEnabled(): boolean {
  return process.env.UCP_MCP_WRITE === "1";
}

function mcpServerCommandExecutionEnabled(): boolean {
  return process.env.UCP_MCP_COMMAND_EXECUTION === "1";
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
