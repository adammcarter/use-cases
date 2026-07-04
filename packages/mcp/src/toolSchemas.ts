export type JsonObject = Record<string, unknown>;

// Closed value-domains mirrored from @adammcarter/use-cases-core so the advertised MCP
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
  description: "Must be true for any ledger mutation. Write tools also require the server to run in write mode (UCM_MCP_WRITE=1)."
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
export function workspaceSchema(properties: JsonObject = {}, required: string[] = []): JsonObject {
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

export const toolInputBase = workspaceSchema();

export const matrixListInputSchema = workspaceSchema({
  value: { type: "array", items: { type: "string", enum: VALUE_TIERS }, description: "Filter to these value tiers." },
  journey_role: { type: "array", items: { type: "string", enum: JOURNEY_ROLES }, description: "Filter to these journey roles." },
  lifecycle: { type: "array", items: { type: "string", enum: LIFECYCLES }, description: "Filter to these lifecycle states." },
  host: { type: "array", items: { type: "string", enum: HOST_SURFACES }, description: "Filter to use cases applicable to these host surfaces." },
  tag: { type: "array", items: { type: "string" }, description: "Filter to use cases carrying any of these tags." },
  changed_path: { type: "array", items: { type: "string" }, description: "Filter to use cases impacted by these changed paths." },
  strict: { type: "boolean", description: "Report ok=false when the matrix is incomplete." }
});

//: @use-case:mcp.surface.declared_tool_schemas
export const useCaseUpsertInputSchema = workspaceSchema({
  file: { type: "string", description: "Workspace-relative matrix file the entry is written into." },
  use_case: useCaseObjectProp,
  expected_hash: expectedHashProp,
  actor_type: actorTypeProp,
  allow_write: allowWriteProp
}, ["file", "use_case"]);
//: @use-case:end mcp.surface.declared_tool_schemas

export const useCaseRemoveInputSchema = workspaceSchema({
  use_case: { type: "string", description: "Canonical use-case id to mark removed." },
  reason: { type: "string", description: "Why the use case is being removed." },
  expected_hash: expectedHashProp,
  actor_type: actorTypeProp,
  allow_write: allowWriteProp
}, ["use_case", "reason"]);

export const evidenceRecordInputSchema = workspaceSchema({
  use_case: { type: "string", description: "Canonical use-case id the evidence attaches to." },
  kind: { type: "string", enum: EVIDENCE_KINDS, description: "Evidence kind (defaults to manual_observation)." },
  result: { type: "string", enum: EVIDENCE_RESULTS, description: "Observed result (defaults to observed)." },
  summary: { type: "string", description: "Human-readable summary of what was observed." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  allow_write: allowWriteProp
}, ["use_case"]);

export const evidenceVoidInputSchema = workspaceSchema({
  evidence: { type: "string", description: "Canonical evidence id to void." },
  expected_head: { type: "string", description: "Expected head event id (optimistic-concurrency guard)." },
  reason: { type: "string", description: "Why the evidence is being voided." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  allow_write: allowWriteProp
}, ["evidence", "expected_head", "reason"]);

export const planInputSchema = workspaceSchema({
  audience: { type: "string", description: "Intended audience label for the plan (default 'reviewer')." },
  timebox_seconds: { type: "integer", minimum: 0, description: "Total presentation budget in seconds (default 600 showcase / 1800 walkthrough)." },
  max_items: { type: "integer", minimum: 1, description: "Cap on the number of selected items." },
  host: { type: "string", enum: HOST_SURFACES, description: "Host surface to plan for (default 'unknown')." },
  changed_path: { type: "array", items: { type: "string" }, description: "Changed paths to bias selection toward impacted use cases." },
  generated_at: { type: "string", description: "ISO-8601 generation timestamp override." },
  strict: { type: "boolean", description: "Block the plan when the matrix or evidence is incomplete." }
});

export const capsuleRunInputSchema = workspaceSchema({
  capsule: { type: "string", description: "Demo capsule id to run." },
  execute_commands: { type: "boolean", description: "Execute capsule commands (requires UCM_MCP_COMMAND_EXECUTION=1)." },
  command_timeout_ms: { type: "integer", minimum: 0, description: "Per-command execution timeout in milliseconds." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["capsule"]);

export const showcaseStartInputSchema = workspaceSchema({
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

export const showcaseStatusInputSchema = workspaceSchema({ run: runProp }, ["run"]);

export const showcaseObservationInputSchema = workspaceSchema({
  run: runProp,
  item: planItemProp,
  text: { type: "string", description: "Observation text for the plan item." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run", "item", "text"]);

export const showcaseVerdictInputSchema = workspaceSchema({
  run: runProp,
  item: planItemProp,
  verdict: { type: "string", enum: VERDICTS, description: "Verdict for the plan item; requires a prior observation." },
  actor_type: actorTypeProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run", "item", "verdict"]);

export const showcaseDecideInputSchema = workspaceSchema({
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

export const showcaseFinishInputSchema = workspaceSchema({
  run: runProp,
  host_surface: hostSurfaceProp,
  idempotency_key: idempotencyKeyProp,
  recorded_at: recordedAtProp,
  allow_write: allowWriteProp
}, ["run"]);

export const showcaseRequestApprovalInputSchema = workspaceSchema({
  run: runProp,
  statement: { type: "string", description: "Draft approval statement echoed into the suggested CLI command." }
}, ["run"]);

export const hostDoctorInputSchema = workspaceSchema({
  host: { type: "string", enum: HOST_NAMES, description: "Host whose profile/projection is checked." }
}, ["host"]);

export const cliEnvelopeSchema = {
  type: "object",
  required: ["schema_version", "protocol_version", "command", "ok", "complete", "data", "diagnostics", "context"]
};
