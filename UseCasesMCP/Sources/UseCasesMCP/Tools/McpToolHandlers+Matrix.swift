import UseCasesCore

/// `use_case_upsert` and `use_case_remove`: the two tools that edit the matrix.
///
/// Both are write-gated twice over before they are reached, and both go
/// through the SAME core mutator the CLI's `matrix upsert` and `matrix remove`
/// use — including its own path containment and its refusal to edit a matrix
/// that is already damaged.
extension McpToolHandlers {
  public static func useCaseUpsert(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "matrix.upsert"
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

    guard let targetFile = McpToolArguments.string(arguments, "file"),
          let useCase = McpToolArguments.object(arguments, "use_case")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing file or use_case.",
        environment: environment,
      )
    }
    let result = try mutate(UseCaseMutationOptions(
      context: workspace,
      operation: .upsert,
      targetFile: targetFile,
      useCase: useCase,
      expectedSemanticHash: McpToolArguments.string(arguments, "expected_hash"),
      actor: McpToolArguments.actorType(arguments).rawValue,
    ))
    return mutationEnvelope(command, result, workspace)
  }

  public static func useCaseRemove(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "matrix.remove"
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

    guard let identifier = McpToolArguments.string(arguments, "use_case"),
          let reason = McpToolArguments.string(arguments, "reason")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing use_case or reason.",
        environment: environment,
      )
    }
    let result = try mutate(UseCaseMutationOptions(
      context: workspace,
      operation: .remove,
      useCaseIdentifier: identifier,
      expectedSemanticHash: McpToolArguments.string(arguments, "expected_hash"),
      reason: reason,
      actor: McpToolArguments.actorType(arguments).rawValue,
    ))
    return mutationEnvelope(command, result, workspace)
  }

  private static func mutate(_ options: UseCaseMutationOptions) throws(McpToolFailure)
    -> UseCaseMutationResult
  {
    let registry = try McpSchemaRegistry.load()
    do throws(UseCaseMatrixError) {
      return try UseCaseMatrixMutator.mutate(options, registry: registry)
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// A mutation that was blocked is neither ok nor complete; the domain's own
  /// diagnostics say why, and they ride on the envelope as well as inside the
  /// result.
  private static func mutationEnvelope(
    _ command: String,
    _ result: UseCaseMutationResult,
    _ workspace: ResolvedWorkspaceContext,
  ) -> CliResult {
    let isSuccessful = result.status != .blocked
    return envelope(
      command,
      result.jsonValue,
      workspace,
      isSuccessful: isSuccessful,
      isComplete: isSuccessful,
      diagnostics: result.diagnostics,
    )
  }
}
