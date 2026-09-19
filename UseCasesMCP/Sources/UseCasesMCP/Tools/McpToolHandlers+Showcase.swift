import UseCasesCore

/// The showcase verbs MCP exposes: `showcase_start`, `showcase_status` and the
/// three recording tools.
///
/// Unlike the CLI, an unpinned `recorded_at` reads the clock rather than a
/// fixed instant, so the corpus pins it.
public extension McpToolHandlers {
  /// A run started from a plan file inside the workspace, or an ad hoc one-row
  /// plan for the use case named by `select`.
  static func showcaseStart(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.start"
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

    if let planFile = McpToolArguments.string(arguments, "plan_file") {
      return try startFromPlanFile(command, planFile, arguments, workspace, environment)
    }
    guard let selected = McpToolArguments.string(arguments, "select") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "showcase.plan_required",
        message: "Only ad hoc select starts are supported.",
        environment: environment,
      )
    }
    return try startAdhoc(command, selected, arguments, workspace, environment)
  }

  private static func startFromPlanFile(
    _ command: String,
    _ planFile: String,
    _ arguments: JSONObject,
    _ workspace: ResolvedWorkspaceContext,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let planPath: String
    switch containedPath(
      command,
      workspaceRoot: workspace.workspaceRoot,
      candidate: planFile,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      planPath = resolved
    }

    do throws(ShowcaseError) {
      let plan = try PlanBinding.loadPlanFile(atPath: planPath)
      let hash = plan["plan_content_hash"]?.stringValue ?? ""
      let result = try ShowcaseRecorder().start(
        plan: plan,
        controlMode: .agentLed,
        recording: recording(
          workspace,
          arguments,
          derivedKey: "mcp:start-plan:\(hash)",
        ),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// The ad hoc path plans exactly the row asked for and refuses when the
  /// planner did not select it — a plan that quietly picked something else
  /// would start a run about the wrong behaviour.
  private static func startAdhoc(
    _ command: String,
    _ selected: String,
    _ arguments: JSONObject,
    _ workspace: ResolvedWorkspaceContext,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let matrixSnapshot = try matrix(workspace)
    let evidenceSnapshot = try evidence(workspace)
    let request = PresentationPlanRequest(
      audience: McpToolArguments.string(arguments, "audience") ?? "reviewer",
      timeboxSeconds: McpToolArguments.number(arguments, "timebox_seconds") ?? 600,
      maxItems: 1,
      hostSurface: McpToolArguments.hostSurface(arguments),
      requestedUseCaseIdentifiers: [selected],
      generatedAt: McpToolArguments.string(arguments, "generated_at")
        ?? McpClock.nowIsoString(),
      freshnessEvaluatedAt: McpToolArguments.string(arguments, "generated_at")
        ?? McpClock.nowIsoString(),
    )
    let planResult = try selectedPlan(
      mode: .showcase,
      workspace,
      matrixSnapshot,
      evidenceSnapshot,
      request,
    )
    guard let plan = planResult.plan,
          plan.selectedItems.contains(where: { item in
            JavaScriptString.identical(item.useCaseIdentifier, selected)
          })
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "showcase.selected_use_case_unavailable",
        message: "Selected use case was not available for an ad hoc plan.",
        environment: environment,
      )
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().start(
        plan: plan.jsonValue.objectValue ?? JSONObject(),
        controlMode: .agentLed,
        recording: recording(workspace, arguments, derivedKey: "mcp:start:\(selected)"),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  static func showcaseStatus(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.status"
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

    guard let runIdentifier = McpToolArguments.string(arguments, "run") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment) {
      return unsafe
    }

    let status = try replayed(workspace, runIdentifier)
    return envelope(command, status.jsonValue, workspace, isComplete: status.isComplete)
  }

  static func showcaseObservation(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.record-observation"
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

    guard let runIdentifier = McpToolArguments.string(arguments, "run"),
          let itemIdentifier = McpToolArguments.string(arguments, "item"),
          let text = McpToolArguments.string(arguments, "text")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run, item, or text.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment)
      ?? unsafeIdentifier(command, "item", itemIdentifier, environment)
    {
      return unsafe
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().recordObservation(
        runIdentifier: runIdentifier,
        planItemIdentifier: itemIdentifier,
        text: text,
        recording: recording(
          workspace,
          arguments,
          derivedKey: "mcp:observation:\(runIdentifier):\(itemIdentifier):\(text)",
        ),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// A verdict names the item's latest observation, so the run is replayed
  /// first and refused when there is none: a judgement with nothing observed
  /// behind it is not evidence.
  static func showcaseVerdict(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.record-verdict"
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

    guard let runIdentifier = McpToolArguments.string(arguments, "run"),
          let itemIdentifier = McpToolArguments.string(arguments, "item"),
          let verdict = McpToolArguments.string(arguments, "verdict")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run, item, or verdict.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment)
      ?? unsafeIdentifier(command, "item", itemIdentifier, environment)
    {
      return unsafe
    }

    let observation: String
    switch try latestObservation(command, workspace, runIdentifier, itemIdentifier, environment) {
    case let .refused(result):
      return result
    case let .resolved(identifier):
      observation = identifier
    }

    return try appendedVerdict(command, arguments, workspace, McpVerdictRequest(
      runIdentifier: runIdentifier,
      itemIdentifier: itemIdentifier,
      verdict: verdict,
      observationEventIdentifier: observation,
    ))
  }

  private static func appendedVerdict(
    _ command: String,
    _ arguments: JSONObject,
    _ workspace: ResolvedWorkspaceContext,
    _ request: McpVerdictRequest,
  ) throws(McpToolFailure) -> CliResult {
    let key = "mcp:verdict:\(request.runIdentifier):"
      + "\(request.itemIdentifier):\(request.verdict)"
    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().recordVerdict(
        runIdentifier: request.runIdentifier,
        planItemIdentifier: request.itemIdentifier,
        verdict: ShowcaseVerdict(rawValue: request.verdict),
        observationEventIdentifiers: [request.observationEventIdentifier],
        recording: recording(workspace, arguments, derivedKey: key),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  static func showcaseDecide(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.decide"
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

    guard let runIdentifier = McpToolArguments.string(arguments, "run"),
          let verdictEvent = McpToolArguments.string(arguments, "verdict_event"),
          let decision = McpToolArguments.string(arguments, "decision"),
          let reason = McpToolArguments.string(arguments, "reason")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run, verdict_event, decision, or reason.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment) {
      return unsafe
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().recordFailureDecision(
        runIdentifier: runIdentifier,
        verdictEventIdentifier: verdictEvent,
        decision: ShowcaseFailureDecision(rawValue: decision),
        reason: reason,
        recording: recording(
          workspace,
          arguments,
          derivedKey: "mcp:decision:\(runIdentifier):\(verdictEvent):\(decision)",
        ),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// Finishing is always recorded as the agent: the actor is hardcoded, not
  /// taken from the arguments.
  static func showcaseFinish(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.finish"
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

    guard let runIdentifier = McpToolArguments.string(arguments, "run") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment) {
      return unsafe
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().finish(
        runIdentifier: runIdentifier,
        recording: recording(
          workspace,
          arguments,
          actorType: .agent,
          derivedKey: "mcp:finish:\(runIdentifier)",
        ),
      )
      return showcaseEnvelope(command, result, workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// The event id of the item's latest observation. An item with none —
  /// `latest_observation_event_id` is null until the first — cannot be judged.
  private static func latestObservation(
    _ command: String,
    _ workspace: ResolvedWorkspaceContext,
    _ runIdentifier: String,
    _ itemIdentifier: String,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> ObservationLookup {
    let status = try replayed(workspace, runIdentifier)
    let item = status.items.first { candidate in
      candidate.planItemIdentifier == .string(itemIdentifier)
    }
    guard let observation = item?.latestObservationEventIdentifier?.stringValue else {
      return .refused(McpErrorEnvelope.make(
        command: command,
        code: "showcase.verdict_requires_observation",
        message: "Verdict requires a prior observation.",
        environment: environment,
      ))
    }
    return .resolved(observation)
  }

  /// The observation a verdict rests on, or the refusal that stands in for it.
  enum ObservationLookup {
    case resolved(String)
    case refused(CliResult)
  }

  internal static func replayed(
    _ workspace: ResolvedWorkspaceContext,
    _ runIdentifier: String,
  ) throws(McpToolFailure) -> ShowcaseRunStatus {
    do throws(ShowcaseError) {
      return try ShowcaseReplay.replay(context: workspace, runIdentifier: runIdentifier)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// The recording every appending tool builds: the argument's actor unless
  /// the tool fixes one, the MCP host surface, and the caller's idempotency
  /// key or the derived one.
  internal static func recording(
    _ workspace: ResolvedWorkspaceContext,
    _ arguments: JSONObject,
    actorType: ShowcaseActorType? = nil,
    derivedKey: String,
  ) -> ShowcaseRecording {
    ShowcaseRecording(
      context: workspace,
      actorType: actorType ?? McpToolArguments.actorType(arguments),
      hostSurface: McpToolArguments.hostSurface(arguments),
      idempotencyKey: McpToolArguments.string(arguments, "idempotency_key") ?? derivedKey,
      recordedAt: McpToolArguments.string(arguments, "recorded_at") ?? McpClock.nowIsoString(),
    )
  }

  internal static func showcaseEnvelope(
    _ command: String,
    _ result: ShowcaseAppendResult,
    _ workspace: ResolvedWorkspaceContext,
  ) -> CliResult {
    envelope(command, result.jsonValue, workspace, isComplete: result.status.isComplete)
  }
}
