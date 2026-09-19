import UseCasesCore

/// `showcase status`, `request-approval`, `approve`, `reject` and `correct`.
extension ShowcaseCommands {
  /// Replay, with an embedded approval token verified when the workspace or a
  /// flag supplies the key material. Without it replay fails closed and a
  /// signed approval reads pending.
  static func runStatus(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.status"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]), !runIdentifier.isEmpty else {
      return refusal(command, "cli_invalid_arguments", "Missing --run.")
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
      return unsafe
    }

    let trust: ShowcaseTrustMaterial?
    do throws(CommandFailure) {
      trust = try ShowcaseTrustMaterial.load(flags: context.flags, workspace: workspace)
    } catch {
      return failed(command, error)
    }
    let status: ShowcaseRunStatus
    do throws(ShowcaseError) {
      status = try ShowcaseReplay.replay(
        context: workspace,
        runIdentifier: runIdentifier,
        trust: trust?.resolvers ?? .none,
      )
    } catch {
      return caught(command, error)
    }
    let result = CliResult.make(
      command: command,
      data: status.jsonValue,
      isSuccessful: true,
      isComplete: status.isComplete,
      diagnostics: trust?.diagnostics ?? [],
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  /// The minted request IS the output: no result envelope, as the human who
  /// signs it out-of-band feeds the file straight to `approve-run`.
  static func runRequestApproval(_ context: HandlerContext) throws(CommandFailure)
    -> CommandOutput
  {
    let command = "showcase.request-approval"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]), !runIdentifier.isEmpty else {
      return refusal(command, "cli_invalid_arguments", "Missing --run.")
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
      return unsafe
    }

    do throws(ShowcaseError) {
      let binding = try ApprovalBinding.binding(
        context: workspace,
        runIdentifier: runIdentifier,
      )
      let request = try ApprovalTokens().mintRequest(binding: binding)
      return CommandOutput(envelope: .object(request), exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  static func runApprove(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.approve"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runIdentifier: String
    let statement: String
    switch decided(command, context.flags, missing: nil) {
    case let .refused(output):
      return output
    case let .value(values):
      (runIdentifier, statement) = values
    }

    // F3: a signed token is by definition a USER sign-off, so it forces the
    // actor. Trust is COMPUTED by the verify+append core, never asserted here.
    let bundle: (token: JSONValue, trust: ShowcaseTrustMaterial)?
    do throws(CommandFailure) {
      bundle = try ShowcaseTrustMaterial.tokenBundle(flags: context.flags, workspace: workspace)
    } catch {
      return failed(command, error)
    }
    let request = ShowcaseApprovalRequest(
      runIdentifier: runIdentifier,
      statement: statement,
      approvalToken: bundle?.token,
      resolvers: bundle?.trust.resolvers ?? .none,
      recording: recording(
        workspace,
        context.flags,
        actorType: bundle == nil ? actorType(context.flags, default: .agent) : .user,
        derivedKey: "cli:approve:\(runIdentifier):\(statement)",
        defaultRecordedAt: "2026-06-25T12:04:00.000Z",
      ),
    )
    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().approve(request, decision: .approved)
      // EXIT PARITY: the exit comes from the recorded run state, and the
      // envelope's `ok` follows it so both renderings agree.
      let exitCode = approvalExitCode(result.status)
      return output(
        command,
        result,
        workspace,
        exitCode: exitCode,
        isSuccessful: exitCode == 0,
        diagnostics: bundle?.trust.diagnostics ?? [],
      )
    } catch {
      return caught(command, error)
    }
  }

  /// The run and the statement an approval or rejection needs, with the id
  /// checked before it can become a path segment. `approve` words its missing
  /// statement on its own; `reject` names both flags in one message.
  private static func decided(
    _ command: String,
    _ flags: ParsedFlags,
    missing: String?,
  ) -> CommandStep<(run: String, statement: String)> {
    let runIdentifier = string(flags["run"]) ?? ""
    let statement = string(flags["statement"]) ?? ""
    if let missing {
      guard !runIdentifier.isEmpty, !statement.isEmpty else {
        return .refused(refusal(command, "cli_invalid_arguments", missing))
      }
    } else {
      guard !runIdentifier.isEmpty else {
        return .refused(refusal(command, "cli_invalid_arguments", "Missing --run."))
      }
      guard !statement.isEmpty else {
        return .refused(refusal(
          command,
          "cli_invalid_arguments",
          "Missing --statement (required: the human-readable approval statement).",
        ))
      }
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
      return .refused(unsafe)
    }
    return .value((runIdentifier, statement))
  }

  /// A rejection is always exit 1 and always `ok`: it recorded what it was
  /// asked to record.
  static func runReject(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.reject"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runIdentifier: String
    let statement: String
    switch decided(command, context.flags, missing: "Missing --run or --statement.") {
    case let .refused(output):
      return output
    case let .value(values):
      (runIdentifier, statement) = values
    }

    let bundle: (token: JSONValue, trust: ShowcaseTrustMaterial)?
    do throws(CommandFailure) {
      bundle = try ShowcaseTrustMaterial.tokenBundle(flags: context.flags, workspace: workspace)
    } catch {
      return failed(command, error)
    }
    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().reject(ShowcaseApprovalRequest(
        runIdentifier: runIdentifier,
        statement: statement,
        approvalToken: bundle?.token,
        resolvers: bundle?.trust.resolvers ?? .none,
        recording: recording(
          workspace,
          context.flags,
          actorType: bundle == nil ? actorType(context.flags, default: .user) : .user,
          derivedKey: "cli:reject:\(runIdentifier):\(statement)",
          defaultRecordedAt: "2026-06-25T12:04:30.000Z",
        ),
      ))
      return output(
        command,
        result,
        workspace,
        exitCode: 1,
        diagnostics: bundle?.trust.diagnostics ?? [],
      )
    } catch {
      return caught(command, error)
    }
  }

  static func runCorrect(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.correct"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]),
          let targetEvent = string(context.flags["targetEvent"]),
          let verdict = string(context.flags["verdict"]),
          let reason = string(context.flags["reason"]),
          !runIdentifier.isEmpty, !targetEvent.isEmpty, !verdict.isEmpty, !reason.isEmpty
    else {
      return refusal(
        command,
        "cli_invalid_arguments",
        "Missing --run, --target-event, --verdict, or --reason.",
      )
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
      return unsafe
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().correctVerdict(
        runIdentifier: runIdentifier,
        targetEventIdentifier: targetEvent,
        correctedVerdict: ShowcaseVerdict(rawValue: verdict),
        reason: reason,
        recording: recording(
          workspace,
          context.flags,
          actorType: actorType(context.flags, default: .agent),
          derivedKey: "cli:correct:\(runIdentifier):\(targetEvent):\(verdict)",
          defaultRecordedAt: "2026-06-25T12:04:45.000Z",
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  /// A key-material failure is reported as the TypeScript's
  /// `showcaseCaughtError` reports it: the code it carries, exit 1.
  private static func failed(
    _ command: String,
    _ failure: CommandFailure,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: failure.code,
        message: failure.message,
      ),
      exitCode: 1,
    )
  }
}
