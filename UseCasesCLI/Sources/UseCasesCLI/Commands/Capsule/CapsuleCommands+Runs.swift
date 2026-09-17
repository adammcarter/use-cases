import UseCasesCore

/// The capsule handlers: each loads `demo-capsules/` afresh, and `run` is the
/// only one that writes.
extension CapsuleCommands {
  /// Always `ok`, even when a capsule is broken; the diagnostics carry it.
  static func runList(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "capsule.list"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try load(workspace)
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(snapshot.isComplete)),
      ("capsules", .array(snapshot.capsules.map(entry))),
    ]))
    let result = CliResult.make(
      command: command,
      data: data,
      isSuccessful: true,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  /// The whole snapshot, and `ok` only when nothing is broken.
  static func runValidate(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "capsule.validate"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try load(workspace)
    let result = CliResult.make(
      command: command,
      data: snapshot.jsonValue,
      isSuccessful: snapshot.isComplete,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: snapshot.isComplete ? 0 : 1)
  }

  /// A plan for one capsule: blocked integrity exits 3, a capsule that is not
  /// there 1.
  static func runPlan(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "capsule.plan"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let capsuleIdentifier = identifier(context.flags) else {
      return missingCapsule(command)
    }

    let registry = try SchemaRegistryLoader.load()
    let result: CapsulePlanResult
    do throws(DemoCapsuleError) {
      result = try DemoCapsulePlanner.plan(
        context: workspace,
        capsuleIdentifier: capsuleIdentifier,
        registry: registry,
      )
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
    let isGenerated = result.outcome == .generated
    let output = CliResult.make(
      command: command,
      data: result.jsonValue,
      isSuccessful: isGenerated,
      isComplete: isGenerated && (result.planResult?.plan?.isComplete ?? false),
      diagnostics: result.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    let exitCode: Int32 = switch result.outcome {
    case .generated: 0
    case .integrityBlocked: 3
    default: 1
    }
    return CommandOutput(result: output, exitCode: exitCode)
  }

  /// Perform the capsule. A blocked run exits 4 when a command's working
  /// directory escaped the workspace and 1 otherwise; a performed run exits 1
  /// when any command missed its expected exit code.
  static func runRun(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "capsule.run"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let capsuleIdentifier = identifier(context.flags) else {
      return missingCapsule(command)
    }

    let registry = try SchemaRegistryLoader.load()
    var options = DemoCapsuleRunOptions(
      context: workspace,
      capsuleIdentifier: capsuleIdentifier,
      isExecutingCommands: context.flags["executeCommands"] == .boolean(true),
      actorType: .agent,
      hostSurface: hostSurface,
      idempotencyKey: PlanCommands.string(context.flags["idempotencyKey"]),
    )
    if let recordedAt = PlanCommands.string(context.flags["recordedAt"]) {
      options.recordedAt = recordedAt
    }
    if let timeout = PlanCommands.number(context.flags["commandTimeoutMs"]) {
      options.commandTimeoutMilliseconds = timeout
    }

    let result: DemoCapsuleRunResult
    do throws(DemoCapsuleError) {
      result = try DemoCapsuleRunner(registry: registry, environment: context.environment)
        .run(options)
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
    let isSuccessful = result.outcome != .blocked
    let output = CliResult.make(
      command: command,
      data: result.jsonValue,
      isSuccessful: isSuccessful,
      isComplete: result.isComplete,
      diagnostics: result.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: output, exitCode: exitCode(of: result, isSuccessful: isSuccessful))
  }

  private static func exitCode(
    of result: DemoCapsuleRunResult,
    isSuccessful: Bool,
  ) -> Int32 {
    guard isSuccessful else {
      let hasEscape = result.diagnostics.contains { diagnostic in
        diagnostic.code == "capsule.command_cwd_escape"
      }
      return hasEscape ? 4 : 1
    }
    let hasUnexpectedExit = result.commandResults.contains { command in
      !command.isExpectedExitCode
    }
    return hasUnexpectedExit ? 1 : 0
  }

  /// `capsule list`'s own projection of one loaded capsule, read from the
  /// document as recorded.
  private static func entry(_ loaded: LoadedDemoCapsule) -> JSONValue {
    var object = JSONObject()
    object["capsule_id"] = loaded.capsule["capsule_id"]
    object["title"] = loaded.capsule["title"]
    object["mode"] = loaded.capsule["mode"]
    object["audience"] = loaded.capsule["audience"]
    object["timebox_seconds"] = loaded.capsule["timebox_seconds"]
    object["item_count"] = .number(Double(loaded.definition.items.count))
    object["path"] = .string(loaded.path)
    object["semantic_hash"] = .string(loaded.semanticHash)
    return .object(object)
  }

  private static func load(_ workspace: ResolvedWorkspaceContext) throws(CommandFailure)
    -> CapsuleSnapshot
  {
    let registry = try SchemaRegistryLoader.load()
    do throws(DemoCapsuleError) {
      return try DemoCapsuleLoader.load(context: workspace, registry: registry)
    } catch {
      throw CommandFailure(code: error.code, message: error.message)
    }
  }

  private static func identifier(_ flags: ParsedFlags) -> String? {
    guard let value = PlanCommands.string(flags["capsule"]), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func missingCapsule(_ command: String) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing --capsule.",
      ),
      exitCode: 2,
    )
  }
}
