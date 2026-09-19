import UseCasesCore

/// `plan_showcase`, `plan_walkthrough` and `capsule_run`.
public extension McpToolHandlers {
  /// One selector for both plan tools, called with the profile the tool name
  /// carries — the TypeScript's shared `planPresentation`.
  static func planPresentation(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
    mode: PresentationMode,
  ) throws(McpToolFailure) -> CliResult {
    let command = "plan.\(mode.rawValue)"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    let matrixSnapshot = try matrix(workspace)
    let evidenceSnapshot = try evidence(workspace)
    let request = PresentationPlanRequest(
      audience: McpToolArguments.string(arguments, "audience") ?? "reviewer",
      timeboxSeconds: McpToolArguments.number(arguments, "timebox_seconds")
        ?? (mode == .showcase ? 600 : 1800),
      maxItems: McpToolArguments.number(arguments, "max_items"),
      hostSurface: McpToolArguments.string(arguments, "host") ?? "unknown",
      changedPaths: McpToolArguments.strings(arguments, "changed_path"),
      generatedAt: McpToolArguments.string(arguments, "generated_at"),
      isStrict: McpToolArguments.boolean(arguments, "strict"),
    )
    let result = try selectedPlan(mode: mode, workspace, matrixSnapshot, evidenceSnapshot, request)
    // `ok` covers everything but a blocked plan; `complete` is the plan's own,
    // and for an empty eligible set the input's.
    return envelope(
      command,
      result.jsonValue,
      workspace,
      isSuccessful: result.outcome != .integrityBlocked,
      isComplete: result.plan?.isComplete
        ?? (result.outcome == .noEligibleItems
          && matrixSnapshot.isComplete
          && evidenceSnapshot.isComplete),
      diagnostics: matrixSnapshot.diagnostics + evidenceSnapshot.diagnostics,
    )
  }

  internal static func selectedPlan(
    mode: PresentationMode,
    _ workspace: ResolvedWorkspaceContext,
    _ matrix: MatrixSnapshot,
    _ evidence: EvidenceSnapshot,
    _ request: PresentationPlanRequest,
  ) throws(McpToolFailure) -> PresentationPlanResult {
    do throws(PresentationError) {
      return switch mode {
      case .showcase:
        try PresentationPlanner.selectShowcasePlan(
          context: workspace,
          matrix: matrix,
          evidence: evidence,
          request: request,
        )
      case .walkthrough:
        try PresentationPlanner.selectWalkthroughPlan(
          context: workspace,
          matrix: matrix,
          evidence: evidence,
          request: request,
        )
      }
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// `capsule_run`. Executing the capsule's commands needs a THIRD lock beyond
  /// the two write ones — `UCM_MCP_COMMAND_EXECUTION=1` — checked before the
  /// handler is reached.
  static func capsuleRun(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "capsule.run"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let capsuleIdentifier = McpToolArguments.string(arguments, "capsule") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing capsule.",
        environment: environment,
      )
    }
    var options = DemoCapsuleRunOptions(
      context: workspace,
      capsuleIdentifier: capsuleIdentifier,
      isExecutingCommands: McpToolArguments.boolean(arguments, "execute_commands"),
      actorType: McpToolArguments.actorType(arguments),
      hostSurface: McpToolArguments.hostSurface(arguments),
      idempotencyKey: McpToolArguments.string(arguments, "idempotency_key"),
    )
    if let recordedAt = McpToolArguments.string(arguments, "recorded_at") {
      options.recordedAt = recordedAt
    }
    if let timeout = McpToolArguments.number(arguments, "command_timeout_ms") {
      options.commandTimeoutMilliseconds = timeout
    }

    let registry = try McpSchemaRegistry.load()
    let result: DemoCapsuleRunResult
    do throws(DemoCapsuleError) {
      result = try DemoCapsuleRunner(registry: registry, environment: environment.variables)
        .run(options)
    } catch {
      throw McpToolFailure(error)
    }
    return envelope(
      command,
      result.jsonValue,
      workspace,
      isSuccessful: result.outcome != .blocked,
      isComplete: result.isComplete,
      diagnostics: result.diagnostics,
    )
  }
}
