import UseCasesCore

/// The appending verbs other than `start`: an observation, a verdict, a
/// failure decision, pause, resume and finish. Each resolves the workspace,
/// checks the flags the TypeScript checks in its order, and hands the recorder
/// the run.
extension ShowcaseCommands {
  static func runRecordObservation(_ context: HandlerContext) throws(CommandFailure)
    -> CommandOutput
  {
    let command = "showcase.record-observation"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]),
          let itemIdentifier = string(context.flags["item"]),
          let text = string(context.flags["text"]),
          !runIdentifier.isEmpty, !itemIdentifier.isEmpty, !text.isEmpty
    else {
      return refusal(command, "cli_invalid_arguments", "Missing --run, --item, or --text.")
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier)
      ?? unsafeIdentifier(command, "--item", itemIdentifier)
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
          context.flags,
          derivedKey: "cli:observation:\(runIdentifier):\(itemIdentifier):\(text)",
          defaultRecordedAt: "2026-06-25T12:01:00.000Z",
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  /// A verdict names the item's latest observation, so the run is replayed
  /// first and refused when there is none.
  static func runRecordVerdict(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.record-verdict"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]),
          let itemIdentifier = string(context.flags["item"]),
          let verdict = string(context.flags["verdict"]),
          !runIdentifier.isEmpty, !itemIdentifier.isEmpty, !verdict.isEmpty
    else {
      return refusal(command, "cli_invalid_arguments", "Missing --run, --item, or --verdict.")
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier)
      ?? unsafeIdentifier(command, "--item", itemIdentifier)
    {
      return unsafe
    }

    let observation: String
    switch latestObservation(command, workspace, runIdentifier, itemIdentifier) {
    case let .refused(output):
      return output
    case let .value(identifier):
      observation = identifier
    }

    do throws(ShowcaseError) {
      let result = try ShowcaseRecorder().recordVerdict(
        runIdentifier: runIdentifier,
        planItemIdentifier: itemIdentifier,
        verdict: ShowcaseVerdict(rawValue: verdict),
        observationEventIdentifiers: [observation],
        recording: recording(
          workspace,
          context.flags,
          actorType: actorType(context.flags, default: .agent),
          derivedKey: "cli:verdict:\(runIdentifier):\(itemIdentifier):\(verdict)",
          defaultRecordedAt: "2026-06-25T12:02:00.000Z",
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  /// The event id of the item's latest observation. A verdict names it, so an
  /// item with none — `latest_observation_event_id` is null until the first —
  /// cannot be judged.
  private static func latestObservation(
    _ command: String,
    _ workspace: ResolvedWorkspaceContext,
    _ runIdentifier: String,
    _ itemIdentifier: String,
  ) -> CommandStep<String> {
    let status: ShowcaseRunStatus
    do throws(ShowcaseError) {
      status = try ShowcaseReplay.replay(context: workspace, runIdentifier: runIdentifier)
    } catch {
      return .refused(caught(command, error))
    }
    let item = status.items.first { candidate in
      candidate.planItemIdentifier == .string(itemIdentifier)
    }
    guard let observation = item?.latestObservationEventIdentifier?.stringValue else {
      return .refused(refusal(
        command,
        "showcase.verdict_requires_observation",
        "Verdict requires a prior observation.",
        exitCode: 1,
      ))
    }
    return .value(observation)
  }

  static func runDecide(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.decide"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    guard let runIdentifier = string(context.flags["run"]),
          let verdictEvent = string(context.flags["verdictEvent"]),
          let decision = string(context.flags["decision"]),
          let reason = string(context.flags["reason"]),
          !runIdentifier.isEmpty, !verdictEvent.isEmpty, !decision.isEmpty, !reason.isEmpty
    else {
      return refusal(
        command,
        "cli_invalid_arguments",
        "Missing --run, --verdict-event, --decision, or --reason.",
      )
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
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
          context.flags,
          actorType: actorType(context.flags, default: .agent),
          derivedKey: "cli:decision:\(runIdentifier):\(verdictEvent):\(decision)",
          defaultRecordedAt: "2026-06-25T12:02:30.000Z",
        ),
      )
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }

  static func runPause(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    try runTransition(context, isPause: true)
  }

  static func runResume(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    try runTransition(context, isPause: false)
  }

  static func runFinish(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.finish"
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
      let result = try ShowcaseRecorder().finish(
        runIdentifier: runIdentifier,
        recording: recording(
          workspace,
          context.flags,
          derivedKey: "cli:finish:\(runIdentifier)",
          defaultRecordedAt: "2026-06-25T12:03:00.000Z",
        ),
      )
      // Only an outright pass exits 0: waivers and gaps are not this verb's
      // success.
      return output(
        command,
        result,
        workspace,
        exitCode: result.status.runOutcome == "passed" ? 0 : 1,
      )
    } catch {
      return caught(command, error)
    }
  }

  /// Pause and resume differ only in the event they append, their default
  /// reason and the key they derive.
  private static func runTransition(
    _ context: HandlerContext,
    isPause: Bool,
  ) throws(CommandFailure) -> CommandOutput {
    let command = isPause ? "showcase.pause" : "showcase.resume"
    let defaultReason = isPause ? "Paused by operator." : "Resumed by operator."
    let keyPrefix = isPause ? "cli:pause" : "cli:resume"
    let defaultRecordedAt = isPause
      ? "2026-06-25T12:02:45.000Z"
      : "2026-06-25T12:02:50.000Z"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let reason = string(context.flags["reason"]) ?? defaultReason
    guard let runIdentifier = string(context.flags["run"]), !runIdentifier.isEmpty else {
      return refusal(command, "cli_invalid_arguments", "Missing --run.")
    }
    if let unsafe = unsafeIdentifier(command, "--run", runIdentifier) {
      return unsafe
    }

    do throws(ShowcaseError) {
      let recorder = ShowcaseRecorder()
      let recorded = recording(
        workspace,
        context.flags,
        actorType: actorType(context.flags, default: .agent),
        derivedKey: "\(keyPrefix):\(runIdentifier):\(reason)",
        defaultRecordedAt: defaultRecordedAt,
      )
      let result = try isPause
        ? recorder.pause(runIdentifier: runIdentifier, reason: reason, recording: recorded)
        : recorder.resume(runIdentifier: runIdentifier, reason: reason, recording: recorded)
      return output(command, result, workspace, exitCode: 0)
    } catch {
      return caught(command, error)
    }
  }
}
