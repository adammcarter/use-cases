import UseCasesCore

/// `showcase start`: from a saved plan file, or from an ad hoc one-row plan.
extension ShowcaseCommands {
  /// The recorded-at a start stamps when the caller pins none.
  static let startRecordedAt = "2026-06-25T12:00:00.000Z"
  /// The generation instant an ad hoc plan is built at when none is given.
  static let adhocGeneratedAt = "2026-06-25T12:00:00.000Z"

  static func runStart(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.start"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    if let planFile = string(context.flags["planFile"]) {
      return try startFromPlanFile(command, planFile, context, workspace)
    }
    guard context.flags["adhoc"] == .boolean(true),
          let selected = string(context.flags["select"])
    else {
      return refusal(
        command,
        "showcase.plan_required",
        "Only --adhoc --select is supported in P6.",
      )
    }
    return try startAdhoc(command, selected, context, workspace)
  }

  private static func startFromPlanFile(
    _ command: String,
    _ planFile: String,
    _ context: HandlerContext,
    _ workspace: ResolvedWorkspaceContext,
  ) throws(CommandFailure) -> CommandOutput {
    let planPath: String
    switch ContainedPath.resolve(
      command: command,
      workspaceRoot: workspace.workspaceRoot,
      candidate: planFile,
    ) {
    case let .refused(output):
      return output
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
          context.flags,
          derivedKey: "cli:start-plan:\(hash)",
          defaultRecordedAt: startRecordedAt,
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  /// A one-item showcase plan for the row asked for, generated at the instant
  /// the flags name and evaluated for freshness at the same one.
  private static func adhocPlan(
    _ selected: String,
    _ context: HandlerContext,
    _ workspace: ResolvedWorkspaceContext,
  ) throws(CommandFailure) -> PresentationPlanResult {
    let matrix = try MatrixCommands.loadMatrix(workspace)
    let evidence: EvidenceSnapshot
    do throws(EvidenceEventError) {
      evidence = try EvidenceReplay.replay(context: workspace)
    } catch {
      throw CommandFailure(error)
    }
    let generatedAt = string(context.flags["generatedAt"]) ?? adhocGeneratedAt
    do throws(PresentationError) {
      return try PresentationPlanner.selectShowcasePlan(
        context: workspace,
        matrix: matrix,
        evidence: evidence,
        request: PresentationPlanRequest(
          audience: string(context.flags["audience"]) ?? "reviewer",
          timeboxSeconds: PlanCommands.number(context.flags["timebox"]) ?? 600,
          maxItems: 1,
          hostSurface: hostSurface,
          requestedUseCaseIdentifiers: [selected],
          generatedAt: generatedAt,
          freshnessEvaluatedAt: generatedAt,
        ),
      )
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
  }

  /// The ad hoc path plans exactly the row asked for, and refuses when the
  /// planner did not select it.
  private static func startAdhoc(
    _ command: String,
    _ selected: String,
    _ context: HandlerContext,
    _ workspace: ResolvedWorkspaceContext,
  ) throws(CommandFailure) -> CommandOutput {
    let planResult = try adhocPlan(selected, context, workspace)
    guard let plan = planResult.plan,
          plan.selectedItems.contains(where: { item in
            JavaScriptString.identical(item.useCaseIdentifier, selected)
          })
    else {
      return refusal(
        command,
        "showcase.selected_use_case_unavailable",
        "Selected use case was not available for an ad hoc plan.",
        exitCode: 1,
      )
    }
    do throws(ShowcaseError) {
      let clock = SystemShowcaseClock()
      let result = try ShowcaseRecorder(clock: clock).start(
        plan: plan.jsonValue.objectValue ?? JSONObject(),
        controlMode: .agentLed,
        recording: recording(
          workspace,
          context.flags,
          derivedKey: "cli:start:\(selected):\(JavaScriptNumber.text(clock.now()))",
          defaultRecordedAt: startRecordedAt,
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }
}
