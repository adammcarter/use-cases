import UseCasesCore

/// `plan showcase` and `plan walkthrough`: one selector, called with the
/// profile the verb names (the TypeScript's shared `planOutput`).
extension PlanCommands {
  static func runSelection(
    _ context: HandlerContext,
    mode: PresentationMode,
  ) throws(CommandFailure) -> CommandOutput {
    let command = "plan.\(mode.rawValue)"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let matrix = try MatrixCommands.loadMatrix(workspace)
    let evidence: EvidenceSnapshot
    do throws(EvidenceEventError) {
      evidence = try EvidenceReplay.replay(context: workspace)
    } catch {
      throw CommandFailure(error)
    }

    let result = try select(
      mode: mode,
      context: workspace,
      matrix: matrix,
      evidence: evidence,
      request: request(context.flags, mode: mode),
    )
    // `ok` covers everything but a blocked plan; `complete` is the plan's own,
    // and for an empty eligible set the input's.
    let isSuccessful = result.outcome != .integrityBlocked
    let isComplete = result.plan?.isComplete
      ?? (result.outcome == .noEligibleItems && matrix.isComplete && evidence.isComplete)
    let output = CliResult.make(
      command: command,
      data: result.jsonValue,
      isSuccessful: isSuccessful,
      isComplete: isComplete,
      diagnostics: matrix.diagnostics + evidence.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: output, exitCode: exitCode(for: result.outcome))
  }

  /// The request the flags describe: the profile's timebox unless `--timebox`
  /// gives one, and `unknown` as the host surface, which every row matches.
  private static func request(
    _ flags: ParsedFlags,
    mode: PresentationMode,
  ) -> PresentationPlanRequest {
    PresentationPlanRequest(
      audience: string(flags["audience"]) ?? "reviewer",
      timeboxSeconds: number(flags["timebox"]) ?? (mode == .showcase ? 600 : 1800),
      maxItems: number(flags["maxItems"]),
      hostSurface: string(flags["host"]) ?? "unknown",
      changedPaths: strings(flags["changedPath"]),
      generatedAt: string(flags["generatedAt"]),
      isStrict: flags["strict"] == .boolean(true),
    )
  }

  private static func select(
    mode: PresentationMode,
    context: ResolvedWorkspaceContext,
    matrix: MatrixSnapshot,
    evidence: EvidenceSnapshot,
    request: PresentationPlanRequest,
  ) throws(CommandFailure) -> PresentationPlanResult {
    do throws(PresentationError) {
      return switch mode {
      case .showcase:
        try PresentationPlanner.selectShowcasePlan(
          context: context,
          matrix: matrix,
          evidence: evidence,
          request: request,
        )
      case .walkthrough:
        try PresentationPlanner.selectWalkthroughPlan(
          context: context,
          matrix: matrix,
          evidence: evidence,
          request: request,
        )
      }
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
  }

  /// A blocked plan exits 3, an empty selection 1, a plan 0.
  private static func exitCode(for outcome: PresentationPlanOutcome) -> Int32 {
    switch outcome {
    case .integrityBlocked: 3
    case .noEligibleItems: 1
    case .generated: 0
    }
  }

  static func string(_ value: ParsedFlagValue?) -> String? {
    guard case let .string(text) = value else {
      return nil
    }
    return text
  }

  static func number(_ value: ParsedFlagValue?) -> Double? {
    guard case let .number(value) = value else {
      return nil
    }
    return value
  }

  static func strings(_ value: ParsedFlagValue?) -> [String] {
    guard case let .strings(values) = value else {
      return []
    }
    return values
  }
}
