import UseCasesCore

/// `evidence void`: argument and id checks, then the void under the append
/// lock. Unlike `record`, the handler catches the append's failures itself and
/// gives each its own exit code: a stale head 1, damaged history 3, anything
/// else — an inactive aggregate, a reused key, the lock, the filesystem — 6.
extension EvidenceCommands {
  static func runVoid(_ context: HandlerContext) async throws(CommandFailure) -> CommandOutput {
    let command = "evidence.void"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let evidenceIdentifier = truthy(context.flags["evidence"]),
          let expectedHead = truthy(context.flags["expectedHead"]),
          let reason = truthy(context.flags["reason"])
    else {
      return refusal(
        command,
        "cli_invalid_arguments",
        "Missing --evidence, --expected-head, or --reason.",
      )
    }
    // SECURITY: a user-supplied id must be canonical BEFORE it becomes a ledger
    // lookup key.
    guard CanonicalIdentifier.isValid(evidenceIdentifier) else {
      return refusal(
        command,
        "UCM_INVALID_ID",
        "Invalid --evidence '\(evidenceIdentifier)': must be a canonical id "
          + "(lowercase, no path separators, no '..').",
      )
    }

    let options = EvidenceVoidOptions(
      context: workspace,
      evidenceIdentifier: evidenceIdentifier,
      expectedHeadEventIdentifier: expectedHead,
      reason: reason,
      idempotencyKey: string(context.flags["idempotencyKey"])
        ?? "cli:void:\(evidenceIdentifier):\(expectedHead)",
      actorType: .agent,
      hostSurface: hostSurface,
    )
    return await voided(options, command: command, workspace: workspace)
  }

  /// The void itself: appended, or the coded refusal it failed with.
  private static func voided(
    _ options: EvidenceVoidOptions,
    command: String,
    workspace: ResolvedWorkspaceContext,
  ) async -> CommandOutput {
    do throws(EvidenceEventError) {
      let append = try await EvidenceAppender().appendVoid(options)
      let result = CliResult.make(
        command: command,
        data: append.resultData(),
        workspaceRoot: workspace.workspaceRoot,
        dataRoot: workspace.dataRoot,
        componentIdentifier: workspace.componentIdentifier,
      )
      return CommandOutput(result: result, exitCode: 0)
    } catch {
      return CommandOutput(
        result: ErrorEnvelope.make(command: command, code: error.code, message: error.message),
        exitCode: voidExitCode(error),
      )
    }
  }

  private static func voidExitCode(_ error: EvidenceEventError) -> Int32 {
    switch error {
    case .expectedHeadMismatch: 1
    case .ledgerDamaged: 3
    default: 6
    }
  }

  /// A string flag's value when JavaScript reads it as truthy.
  private static func truthy(_ value: ParsedFlagValue?) -> String? {
    guard let text = string(value), !text.isEmpty else {
      return nil
    }
    return text
  }
}
