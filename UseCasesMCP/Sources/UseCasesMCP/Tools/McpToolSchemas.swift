import UseCasesCore

/// The declared input schema of each tool, and the one output schema they all
/// share (packages/mcp/src/toolSchemas.ts).
enum McpToolSchemas {
  static let base = McpSchemaFragments.workspaceSchema()

  static let matrixList = McpSchemaFragments.workspaceSchema([
    ("value", McpSchemaFragments.enumerationArray(
      McpSchemaFragments.valueTiers,
      "Filter to these value tiers.",
    )),
    ("journey_role", McpSchemaFragments.enumerationArray(
      McpSchemaFragments.journeyRoles,
      "Filter to these journey roles.",
    )),
    ("lifecycle", McpSchemaFragments.enumerationArray(
      McpSchemaFragments.lifecycles,
      "Filter to these lifecycle states.",
    )),
    ("host", McpSchemaFragments.enumerationArray(
      McpSchemaFragments.hostSurfaces,
      "Filter to use cases applicable to these host surfaces.",
    )),
    ("tag", McpSchemaFragments.stringArray("Filter to use cases carrying any of these tags.")),
    ("changed_path", McpSchemaFragments.stringArray(
      "Filter to use cases impacted by these changed paths.",
    )),
    ("strict", McpSchemaFragments.boolean("Report ok=false when the matrix is incomplete.")),
  ])

  static let useCaseUpsert = McpSchemaFragments.workspaceSchema([
    ("file", McpSchemaFragments.string(
      "Workspace-relative matrix file the entry is written into.",
    )),
    ("use_case", McpSchemaFragments.useCaseObject),
    ("expected_hash", McpSchemaFragments.expectedHash),
    ("actor_type", McpSchemaFragments.actorType),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["file", "use_case"])

  static let useCaseRemove = McpSchemaFragments.workspaceSchema([
    ("use_case", McpSchemaFragments.string("Canonical use-case id to mark removed.")),
    ("reason", McpSchemaFragments.string("Why the use case is being removed.")),
    ("expected_hash", McpSchemaFragments.expectedHash),
    ("actor_type", McpSchemaFragments.actorType),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["use_case", "reason"])

  static let evidenceRecord = McpSchemaFragments.workspaceSchema([
    ("use_case", McpSchemaFragments.string("Canonical use-case id the evidence attaches to.")),
    ("kind", McpSchemaFragments.enumeration(
      McpSchemaFragments.evidenceKinds,
      "Evidence kind (defaults to manual_observation).",
    )),
    ("result", McpSchemaFragments.enumeration(
      McpSchemaFragments.evidenceResults,
      "Observed result (defaults to observed).",
    )),
    ("summary", McpSchemaFragments.string("Human-readable summary of what was observed.")),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["use_case"])

  static let evidenceVoid = McpSchemaFragments.workspaceSchema([
    ("evidence", McpSchemaFragments.string("Canonical evidence id to void.")),
    ("expected_head", McpSchemaFragments.string(
      "Expected head event id (optimistic-concurrency guard).",
    )),
    ("reason", McpSchemaFragments.string("Why the evidence is being voided.")),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["evidence", "expected_head", "reason"])

  static let plan = McpSchemaFragments.workspaceSchema([
    ("audience", McpSchemaFragments.string(
      "Intended audience label for the plan (default 'reviewer').",
    )),
    ("timebox_seconds", McpSchemaFragments.integer(
      minimum: 0,
      "Total presentation budget in seconds (default 600 showcase / 1800 walkthrough).",
    )),
    ("max_items", McpSchemaFragments.integer(
      minimum: 1,
      "Cap on the number of selected items.",
    )),
    ("host", McpSchemaFragments.enumeration(
      McpSchemaFragments.hostSurfaces,
      "Host surface to plan for (default 'unknown').",
    )),
    ("changed_path", McpSchemaFragments.stringArray(
      "Changed paths to bias selection toward impacted use cases.",
    )),
    ("generated_at", McpSchemaFragments.string("ISO-8601 generation timestamp override.")),
    ("strict", McpSchemaFragments.boolean(
      "Block the plan when the matrix or evidence is incomplete.",
    )),
  ])

  static let capsuleRun = McpSchemaFragments.workspaceSchema([
    ("capsule", McpSchemaFragments.string("Demo capsule id to run.")),
    ("execute_commands", McpSchemaFragments.boolean(
      "Execute capsule commands (requires UCM_MCP_COMMAND_EXECUTION=1).",
    )),
    ("command_timeout_ms", McpSchemaFragments.integer(
      minimum: 0,
      "Per-command execution timeout in milliseconds.",
    )),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["capsule"])

  static let showcaseStart = McpSchemaFragments.workspaceSchema([
    ("select", McpSchemaFragments.string(
      "Use-case id to build an ad hoc single-item plan for (alternative to plan_file).",
    )),
    ("plan_file", McpSchemaFragments.string(
      "Workspace-relative presentation-plan JSON file to start from (alternative to select).",
    )),
    ("audience", McpSchemaFragments.string(
      "Audience label for an ad hoc plan (default 'reviewer').",
    )),
    ("timebox_seconds", McpSchemaFragments.integer(
      minimum: 0,
      "Timebox in seconds for an ad hoc plan (default 600).",
    )),
    ("generated_at", McpSchemaFragments.string("ISO-8601 plan generation timestamp override.")),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ])

  static let showcaseStatus = McpSchemaFragments.workspaceSchema(
    [("run", McpSchemaFragments.run)],
    required: ["run"],
  )

  static let showcaseObservation = McpSchemaFragments.workspaceSchema([
    ("run", McpSchemaFragments.run),
    ("item", McpSchemaFragments.planItem),
    ("text", McpSchemaFragments.string("Observation text for the plan item.")),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["run", "item", "text"])

  static let showcaseVerdict = McpSchemaFragments.workspaceSchema([
    ("run", McpSchemaFragments.run),
    ("item", McpSchemaFragments.planItem),
    ("verdict", McpSchemaFragments.enumeration(
      McpSchemaFragments.verdicts,
      "Verdict for the plan item; requires a prior observation.",
    )),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["run", "item", "verdict"])

  static let showcaseDecide = McpSchemaFragments.workspaceSchema([
    ("run", McpSchemaFragments.run),
    ("verdict_event", McpSchemaFragments.string(
      "Verdict event id the failure decision applies to.",
    )),
    ("decision", McpSchemaFragments.enumeration(
      McpSchemaFragments.failureDecisions,
      "Disposition for a failing/partial item.",
    )),
    ("reason", McpSchemaFragments.string("Why this decision was taken.")),
    ("actor_type", McpSchemaFragments.actorType),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["run", "verdict_event", "decision", "reason"])

  static let showcaseFinish = McpSchemaFragments.workspaceSchema([
    ("run", McpSchemaFragments.run),
    ("host_surface", McpSchemaFragments.hostSurface),
    ("idempotency_key", McpSchemaFragments.idempotencyKey),
    ("recorded_at", McpSchemaFragments.recordedAt),
    ("allow_write", McpSchemaFragments.allowWrite),
  ], required: ["run"])

  static let showcaseRequestApproval = McpSchemaFragments.workspaceSchema([
    ("run", McpSchemaFragments.run),
    ("statement", McpSchemaFragments.string(
      "Draft approval statement echoed into the suggested CLI command.",
    )),
  ], required: ["run"])

  /// Every tool answers the v1 CLI envelope, so they all declare the same
  /// output schema: the eight frozen keys, required.
  static let cliEnvelope = JSONValue.object(JSONObject([
    ("type", .string("object")),
    ("required", .array([
      .string("schema_version"),
      .string("protocol_version"),
      .string("command"),
      .string("ok"),
      .string("complete"),
      .string("data"),
      .string("diagnostics"),
      .string("context"),
    ])),
  ]))
}
