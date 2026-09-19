import UseCasesCore

/// The nineteen tools, in the order `tools/list` declares them, and the gates
/// every call passes (packages/mcp/src/tools.ts).
public enum McpToolCatalog {
  public static let definitions: [McpToolDefinition] = [
    McpToolDefinition(
      name: "doctor_roots",
      command: "doctor.roots",
      description: "Inspect resolved use-cases roots.",
      mutability: .read,
      inputSchema: McpToolSchemas.base,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.doctorRoots(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "matrix_validate",
      command: "matrix.validate",
      description: "Validate use-case matrix files.",
      mutability: .read,
      inputSchema: McpToolSchemas.base,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.matrixValidate(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "matrix_list",
      command: "matrix.list",
      description: "List and filter use cases.",
      mutability: .read,
      inputSchema: McpToolSchemas.matrixList,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.matrixList(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "matrix_status",
      command: "matrix.status",
      description: "Summarize matrix and evidence status.",
      mutability: .read,
      inputSchema: McpToolSchemas.base,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.matrixStatus(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "use_case_upsert",
      command: "matrix.upsert",
      description: "Add or update one use-case entry. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.useCaseUpsert,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.useCaseUpsert(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "use_case_remove",
      command: "matrix.remove",
      description: "Mark one use case removed. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.useCaseRemove,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.useCaseRemove(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "evidence_status",
      command: "evidence.status",
      description: "Replay evidence status.",
      mutability: .read,
      inputSchema: McpToolSchemas.base,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.evidenceStatus(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "evidence_record",
      command: "evidence.record",
      description: "Append an evidence record. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.evidenceRecord,
      handler: { arguments, environment throws(McpToolFailure) in
        try await McpToolHandlers.evidenceRecord(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "evidence_void",
      command: "evidence.void",
      description: "Void an active evidence record. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.evidenceVoid,
      handler: { arguments, environment throws(McpToolFailure) in
        try await McpToolHandlers.evidenceVoid(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "plan_showcase",
      command: "plan.showcase",
      description: "Generate a showcase plan.",
      mutability: .read,
      inputSchema: McpToolSchemas.plan,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.planPresentation(arguments, environment, mode: .showcase)
      },
    ),
    McpToolDefinition(
      name: "plan_walkthrough",
      command: "plan.walkthrough",
      description: "Generate a walkthrough plan.",
      mutability: .read,
      inputSchema: McpToolSchemas.plan,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.planPresentation(arguments, environment, mode: .walkthrough)
      },
    ),
    McpToolDefinition(
      name: "capsule_run",
      command: "capsule.run",
      description: "Run a persisted demo capsule. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.capsuleRun,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.capsuleRun(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_start",
      command: "showcase.start",
      description: "Start an ad hoc showcase run. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.showcaseStart,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseStart(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_status",
      command: "showcase.status",
      description: "Replay showcase run status.",
      mutability: .read,
      inputSchema: McpToolSchemas.showcaseStatus,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseStatus(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_record_observation",
      command: "showcase.record-observation",
      description: "Append a showcase observation. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.showcaseObservation,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseObservation(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_record_verdict",
      command: "showcase.record-verdict",
      description: "Append a showcase verdict. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.showcaseVerdict,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseVerdict(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_decide",
      command: "showcase.decide",
      description: "Append a failure decision. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.showcaseDecide,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseDecide(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_finish",
      command: "showcase.finish",
      description: "Finish a showcase run. Requires allow_write=true.",
      mutability: .write,
      inputSchema: McpToolSchemas.showcaseFinish,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseFinish(arguments, environment)
      },
    ),
    McpToolDefinition(
      name: "showcase_request_approval",
      command: "showcase.request-approval",
      description: "Prepare CLI-mediated user approval instructions without appending approval.",
      mutability: .approvalRequest,
      inputSchema: McpToolSchemas.showcaseRequestApproval,
      handler: { arguments, environment throws(McpToolFailure) in
        try McpToolHandlers.showcaseRequestApproval(arguments, environment)
      },
    ),
  ]

  /// What `tools/list` returns: the descriptors only, never the handlers.
  public static let descriptors = definitions.map(\.descriptor)

  /// Every gate a call passes, in the TypeScript's order — which is observable,
  /// because each refusal has its own code and the FIRST one decides.
  public static func call(
    name: String,
    arguments: JSONObject,
    environment: McpEnvironment,
  ) async -> CliResult {
    guard let definition = definitions.first(where: { $0.name == name }) else {
      return McpErrorEnvelope.make(
        command: "mcp.unknown",
        code: "mcp.tool_unknown",
        message: "Unknown MCP tool '\(name)'.",
        environment: environment,
      )
    }
    if let refusal = refusal(for: definition, arguments, environment) {
      return refusal
    }
    do throws(McpToolFailure) {
      return try await definition.handler(arguments, environment)
    } catch {
      return McpErrorEnvelope.make(
        command: definition.command,
        code: error.code,
        message: error.message,
        environment: environment,
      )
    }
  }

  /// The first gate that refuses this call, or nil when it may run.
  private static func refusal(
    for definition: McpToolDefinition,
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) -> CliResult? {
    // A zero budget aborts before execution. Only an explicit 0; any other
    // number is advisory and nothing enforces it.
    if McpToolArguments.number(arguments, "timeout_ms") == 0 {
      return refused(
        definition,
        environment,
        "mcp.timeout",
        "MCP tool call timed out before execution.",
      )
    }
    if let locked = writeLock(definition, arguments, environment) {
      return locked
    }
    // A third lock, for the one tool that can spawn processes.
    if definition.name == "capsule_run",
       McpToolArguments.boolean(arguments, "execute_commands"),
       !environment.isCommandExecutionEnabled
    {
      return refused(
        definition,
        environment,
        "mcp.server_command_execution_mode_required",
        "MCP server was not started with command execution enabled.",
      )
    }
    // SECURITY: an agent may never claim a human acted.
    if McpToolArguments.isTrustedUserClaim(arguments) {
      return refused(
        definition,
        environment,
        "mcp.trusted_confirmation_required",
        "MCP cannot claim a trusted user actor without host confirmation.",
      )
    }
    return nil
  }

  /// TWO independent write locks, checked call-first. A read-only session that
  /// DID ask for the write is told the session refused; one that did not ask is
  /// told the call refused. A reader can tell which.
  private static func writeLock(
    _ definition: McpToolDefinition,
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) -> CliResult? {
    guard definition.mutability == .write else {
      return nil
    }
    guard arguments["allow_write"] == .bool(true) else {
      return refused(
        definition,
        environment,
        "mcp.write_mode_required",
        "Write tools require allow_write=true.",
      )
    }
    guard environment.isWriteModeEnabled else {
      return refused(
        definition,
        environment,
        "mcp.server_write_mode_required",
        "MCP server was not started with write mode enabled.",
      )
    }
    return nil
  }

  private static func refused(
    _ definition: McpToolDefinition,
    _ environment: McpEnvironment,
    _ code: String,
    _ message: String,
  ) -> CliResult {
    McpErrorEnvelope.make(
      command: definition.command,
      code: code,
      message: message,
      environment: environment,
    )
  }
}
