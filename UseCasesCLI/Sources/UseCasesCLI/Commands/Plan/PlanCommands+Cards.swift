import UseCasesCore

/// `plan cards`: render the cards of a plan already saved in the workspace.
extension PlanCommands {
  static func runCards(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "plan.cards"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let planFile = string(context.flags["planFile"]), !planFile.isEmpty else {
      return CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "cli_invalid_arguments",
          message: "Missing --plan-file.",
        ),
        exitCode: 2,
      )
    }
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

    let plan: JSONObject
    do throws(ShowcaseError) {
      plan = try PlanBinding.loadPlanFile(atPath: planPath)
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
    let data = try cards(of: plan)
    let result = CliResult.make(
      command: command,
      data: data,
      isSuccessful: true,
      isComplete: true,
      diagnostics: [],
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  /// `{ schema_version, plan_id, cards }`, one card per selected item.
  private static func cards(of plan: JSONObject) throws(CommandFailure) -> JSONValue {
    var rendered: [JSONValue] = []
    for value in plan["selected_items"]?.arrayValue ?? [] {
      let item = try PlanCardItem(value)
      do throws(PresentationError) {
        try rendered.append(item.card(PresentationCardRenderer.renderCard(item.item)))
      } catch {
        throw CommandFailure(code: error.code, message: error.message)
      }
    }
    var object = JSONObject()
    object["schema_version"] = .number(1)
    object["plan_id"] = plan["plan_id"]
    object["cards"] = .array(rendered)
    return .object(object)
  }
}
