import UseCasesCore

/// `evidence_status`, `evidence_record` and `evidence_void`.
///
/// Unlike the CLI, none of these catches the append's own failures: a damaged
/// history, a reused idempotency key or a stale head is thrown and reported
/// under its own code by `callMcpTool`.
public extension McpToolHandlers {
  static func evidenceStatus(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "evidence.status"
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

    let snapshot = try evidence(workspace)
    return envelope(
      command,
      snapshot.statusResult(),
      workspace,
      isSuccessful: snapshot.isComplete,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
    )
  }

  /// The row has to resolve before anything is appended: evidence for a use
  /// case that is not in the matrix would be unattachable.
  static func evidenceRecord(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) async throws(McpToolFailure) -> CliResult {
    let command = "evidence.record"
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

    guard let useCaseIdentifier = McpToolArguments.string(arguments, "use_case") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "evidence.use_case.required",
        message: "Missing use_case.",
        environment: environment,
      )
    }
    let resolution = try matrix(workspace).resolveUseCase(useCaseIdentifier)
    guard case let .resolved(_, useCase) = resolution else {
      return McpErrorEnvelope.make(
        command: command,
        code: "evidence.use_case.unresolved",
        message: "Use case '\(useCaseIdentifier)' is \(resolution.kind).",
        environment: environment,
      )
    }

    let kind = McpToolArguments.string(arguments, "kind") ?? "manual_observation"
    let result = McpToolArguments.string(arguments, "result") ?? "observed"
    let options = EvidenceAppendOptions(
      context: workspace,
      idempotencyKey: McpToolArguments.string(arguments, "idempotency_key")
        ?? "mcp:\(useCaseIdentifier):\(kind):\(result)",
      target: EvidenceTarget(
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: nil,
        useCaseSemanticHash: useCase.semanticHash,
      ),
      kind: kind,
      result: result,
      summary: McpToolArguments.string(arguments, "summary")
        ?? "Recorded \(kind) evidence for \(useCaseIdentifier).",
      actorType: McpToolArguments.evidenceActorType(arguments),
      hostSurface: McpToolArguments.hostSurface(arguments),
    )
    let append = try await appended(options)
    return envelope(command, append.resultData(), workspace)
  }

  static func evidenceVoid(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) async throws(McpToolFailure) -> CliResult {
    let command = "evidence.void"
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

    guard let evidenceIdentifier = McpToolArguments.string(arguments, "evidence"),
          let expectedHead = McpToolArguments.string(arguments, "expected_head"),
          let reason = McpToolArguments.string(arguments, "reason")
    else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing evidence, expected_head, or reason.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "evidence", evidenceIdentifier, environment) {
      return unsafe
    }

    let options = EvidenceVoidOptions(
      context: workspace,
      evidenceIdentifier: evidenceIdentifier,
      expectedHeadEventIdentifier: expectedHead,
      reason: reason,
      idempotencyKey: McpToolArguments.string(arguments, "idempotency_key")
        ?? "mcp:void:\(evidenceIdentifier):\(expectedHead)",
      actorType: McpToolArguments.evidenceActorType(arguments),
      hostSurface: McpToolArguments.hostSurface(arguments),
    )
    let append = try await voided(options)
    return envelope(command, append.resultData(), workspace)
  }

  private static func appended(_ options: EvidenceAppendOptions) async throws(McpToolFailure)
    -> EvidenceAppendResult
  {
    do throws(EvidenceEventError) {
      return try await EvidenceAppender().append(options)
    } catch {
      throw McpToolFailure(error)
    }
  }

  private static func voided(_ options: EvidenceVoidOptions) async throws(McpToolFailure)
    -> EvidenceAppendResult
  {
    do throws(EvidenceEventError) {
      return try await EvidenceAppender().appendVoid(options)
    } catch {
      throw McpToolFailure(error)
    }
  }
}
