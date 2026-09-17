import UseCasesCore

/// The twelve `showcase` verbs (packages/cli/src/commands/showcase.ts).
///
/// The verbs that append are declared in `ShowcaseCommands+Recording.swift`
/// and run in `+RecordingRuns.swift`; status, the approval verbs and correct
/// are in `+Approval.swift` and `+ApprovalRuns.swift`. The trust material a
/// signed approval needs is ``ShowcaseTrustMaterial``.
enum ShowcaseCommands {
  static let all = [
    start,
    recordObservation,
    recordVerdict,
    decide,
    pause,
    resume,
    finish,
    status,
    requestApproval,
    approve,
    reject,
    correct,
  ]

  /// Every showcase event the CLI appends names this host surface.
  static let hostSurface = "codex.cli"

  /// A string flag's value, or nil when absent.
  static func string(_ value: ParsedFlagValue?) -> String? {
    PlanCommands.string(value)
  }

  /// An error envelope with the exit code given.
  static func refusal(
    _ command: String,
    _ code: String,
    _ message: String,
    exitCode: Int32 = 2,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(command: command, code: code, message: message),
      exitCode: exitCode,
    )
  }

  /// SECURITY: refuse an id that is not canonical BEFORE it can become a path
  /// segment (`showcase-runs/<run>/events.jsonl`) or a ledger lookup key
  /// (`rejectUnsafeId`). Nil when the value is safe.
  static func unsafeIdentifier(
    _ command: String,
    _ parameterName: String,
    _ value: String,
  ) -> CommandOutput? {
    guard !CanonicalIdentifier.isValid(value) else {
      return nil
    }
    return refusal(
      command,
      "UCM_INVALID_ID",
      "Invalid \(parameterName) '\(value)': must be a canonical id "
        + "(lowercase, no path separators, no '..').",
    )
  }

  /// `writeShowcaseResult`: the run result in the canonical envelope, with the
  /// verb's own exit code. `ok` defaults to true so every existing verb's
  /// envelope is unchanged; `approve` passes its exit parity through.
  static func output(
    _ command: String,
    _ result: ShowcaseAppendResult,
    _ workspace: ResolvedWorkspaceContext,
    exitCode: Int32,
    isSuccessful: Bool = true,
    diagnostics: [Diagnostic] = [],
  ) -> CommandOutput {
    CommandOutput(
      result: CliResult.make(
        command: command,
        data: result.jsonValue,
        isSuccessful: isSuccessful,
        isComplete: result.status.isComplete,
        diagnostics: diagnostics,
        workspaceRoot: workspace.workspaceRoot,
        dataRoot: workspace.dataRoot,
        componentIdentifier: workspace.componentIdentifier,
      ),
      exitCode: exitCode,
    )
  }

  /// `writeCaughtShowcaseError`: a thrown core error under its own code, with
  /// ledger damage exiting 3 and everything else 1.
  static func caught(
    _ command: String,
    _ error: ShowcaseError,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(command: command, code: error.code, message: error.message),
      exitCode: error.code == "showcase_ledger_damaged" ? 3 : 1,
    )
  }

  /// EXIT PARITY: an approval is an unqualified success only when the run is
  /// complete, its approval state is a POSITIVE approval and the run itself
  /// passed. Approving a rejected, pending, stale or failed run must not read
  /// as exit 0.
  static func approvalExitCode(_ status: ShowcaseRunStatus) -> Int32 {
    let isPositive = ["approved", "approved_with_known_gaps", "not_required"]
      .contains(status.approvalState)
    let isPassing = ["passed", "passed_with_waivers"].contains(status.runOutcome)
    return status.isComplete && isPositive && isPassing ? 0 : 1
  }

  /// The recording every appending verb builds: the CLI's actor and host, the
  /// idempotency key (its own or the derived one) and the recorded-at stamp.
  static func recording(
    _ workspace: ResolvedWorkspaceContext,
    _ flags: ParsedFlags,
    actorType: ShowcaseActorType = .agent,
    derivedKey: String,
    defaultRecordedAt: String,
  ) -> ShowcaseRecording {
    ShowcaseRecording(
      context: workspace,
      actorType: actorType,
      hostSurface: hostSurface,
      idempotencyKey: string(flags["idempotencyKey"]) ?? derivedKey,
      recordedAt: string(flags["recordedAt"]) ?? defaultRecordedAt,
    )
  }

  /// An `--actor` value as the TypeScript passes it: through unchecked, so an
  /// unrecognised one is recorded as given.
  static func actorType(
    _ flags: ParsedFlags,
    default fallback: ShowcaseActorType,
  ) -> ShowcaseActorType {
    guard let text = string(flags["actor"]) else {
      return fallback
    }
    return ShowcaseActorType(rawValue: text)
  }
}
