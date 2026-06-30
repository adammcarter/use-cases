import type { CliResult } from "@use-cases-plugin/core";
import {
  type JsonObject,
  cliEnvelopeSchema,
  toolInputBase,
  matrixListInputSchema,
  useCaseUpsertInputSchema,
  useCaseRemoveInputSchema,
  evidenceRecordInputSchema,
  evidenceVoidInputSchema,
  planInputSchema,
  capsuleRunInputSchema,
  showcaseStartInputSchema,
  showcaseStatusInputSchema,
  showcaseObservationInputSchema,
  showcaseVerdictInputSchema,
  showcaseDecideInputSchema,
  showcaseFinishInputSchema,
  showcaseRequestApprovalInputSchema,
  hostDoctorInputSchema
} from "./toolSchemas.js";
import {
  boolArg,
  capsuleRun,
  doctorRoots,
  errorEnvelope,
  evidenceRecord,
  evidenceStatus,
  evidenceVoid,
  hostDoctor,
  isTrustedUserClaim,
  matrixList,
  matrixStatus,
  matrixValidate,
  mcpServerCommandExecutionEnabled,
  mcpServerWriteModeEnabled,
  numberArg,
  planPresentation,
  showcaseDecide,
  showcaseFinish,
  showcaseObservation,
  showcaseRequestApproval,
  showcaseStart,
  showcaseStatus,
  showcaseVerdict,
  useCaseRemove,
  useCaseUpsert
} from "./toolHandlers.js";

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
