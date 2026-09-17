import UseCasesCore

/// `evidence record`: resolve the row, optionally PERFORM the behaviour, append
/// the event, then say back how strong the evidence is.
///
/// Nothing here catches the append's own failures (damaged history, a reused
/// idempotency key, the lock): as in the TypeScript they are thrown, and the
/// dispatcher reports them with exit 1.
extension EvidenceCommands {
  static func runRecord(_ context: HandlerContext) async throws(CommandFailure) -> CommandOutput {
    let command = "evidence.record"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let useCaseIdentifier = string(context.flags["useCase"]),
          !useCaseIdentifier.isEmpty
    else {
      return refusal(command, "evidence.use_case.required", "Missing --use-case.")
    }
    let matrix = try MatrixCommands.loadMatrix(workspace)
    let resolution = matrix.resolveUseCase(useCaseIdentifier)
    guard case let .resolved(_, useCase) = resolution else {
      return refusal(
        command,
        "evidence.use_case.unresolved",
        "Use case '\(useCaseIdentifier)' is \(resolution.kind).",
      )
    }

    let performed: EvidencePerformedCommand?
    switch try performedRun(context, workspace: workspace, command: command) {
    case let .refused(output):
      return output
    case let .ran(run):
      performed = run
    }

    let append = try await EvidenceCommands.append(recordOptions(
      context: context,
      workspace: workspace,
      useCaseIdentifier: useCaseIdentifier,
      semanticHash: useCase.semanticHash,
      performed: performed,
    ))
    return try output(append, performed: performed, workspace: workspace, command: command)
  }

  /// The appended event, with the replay the assurance diagnostic reads.
  private static func output(
    _ append: EvidenceAppendResult,
    performed: EvidencePerformedCommand?,
    workspace: ResolvedWorkspaceContext,
    command: String,
  ) throws(CommandFailure) -> CommandOutput {
    let snapshot: EvidenceSnapshot
    do throws(EvidenceEventError) {
      snapshot = try EvidenceReplay.replay(context: workspace)
    } catch {
      throw CommandFailure(error)
    }
    let result = CliResult.make(
      command: command,
      data: append.resultData(),
      diagnostics: diagnostics(for: performed, appended: append, in: snapshot),
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  /// A performed run, or the refusal that stands in for it.
  private enum PerformedRun {
    case ran(EvidencePerformedCommand?)
    case refused(CommandOutput)
  }

  /// `--perform`: everything after a standalone `--` is spawned here, in the
  /// workspace root. Without the flag there is no run at all.
  private static func performedRun(
    _ context: HandlerContext,
    workspace: ResolvedWorkspaceContext,
    command: String,
  ) throws(CommandFailure) -> PerformedRun {
    guard context.flags["perform"] == .boolean(true) else {
      return .ran(nil)
    }
    let argv = EvidencePerformedCommand.command(after: context.arguments)
    guard let executable = argv.first else {
      return .refused(refusal(
        command,
        "evidence.run.command_required",
        "--perform needs a command: `uc evidence record --use-case <id> "
          + "--perform -- <cmd> [args...]`.",
      ))
    }
    return try .ran(EvidencePerformedCommand.perform(
      executable: executable,
      arguments: Array(argv.dropFirst()),
      workingDirectory: workspace.workspaceRoot,
      environment: context.environment,
    ))
  }

  /// What was run, said back, and how strong the projected evidence is. The
  /// append result's shape is schema-locked, so both ride as info diagnostics.
  private static func diagnostics(
    for performed: EvidencePerformedCommand?,
    appended append: EvidenceAppendResult,
    in snapshot: EvidenceSnapshot,
  ) -> [Diagnostic] {
    let aggregate = snapshot.aggregates.first { aggregate in
      aggregate.evidenceIdentifier.utf16.elementsEqual(append.event.aggregateIdentifier.utf16)
    }
    let assuranceClass = aggregate?.assurance["class"]?.stringValue ?? ""
    var diagnostics: [Diagnostic] = []
    if let performed {
      diagnostics.append(information(
        "evidence.performed_run",
        "Performed `\(performed.commandLine)` and observed exit \(performed.exitCode).",
      ))
    }
    if !assuranceClass.isEmpty {
      diagnostics.append(information(
        "evidence.assurance_class",
        assuranceClassMessage(assuranceClass),
      ))
    }
    return diagnostics
  }

  /// The event to append: flags first, then the defaults a performed run or a
  /// self-reported record implies. An empty flag value is kept, as `??` keeps
  /// it.
  private static func recordOptions(
    context: HandlerContext,
    workspace: ResolvedWorkspaceContext,
    useCaseIdentifier: String,
    semanticHash: String,
    performed: EvidencePerformedCommand?,
  ) -> EvidenceAppendOptions {
    let flags = context.flags
    let kind = string(flags["kind"]) ?? (performed == nil ? "manual_observation" : "command_result")
    let result = string(flags["result"]) ?? performed.map { run in
      run.exitCode == 0 ? "pass" : "fail"
    } ?? "observed"
    let summary = string(flags["summary"]) ?? performed.map { run in
      "Ran `\(run.commandLine)` for \(useCaseIdentifier): exit \(run.exitCode), "
        + "stdout \(run.standardOutputDigest), stderr \(run.standardErrorDigest)."
    } ?? "Recorded \(kind) evidence for \(useCaseIdentifier)."
    let idempotencyKey = string(flags["idempotencyKey"]) ?? performed.map { run in
      "cli:run:\(useCaseIdentifier):\(run.standardOutputDigest):\(run.exitCode)"
    } ?? "cli:\(useCaseIdentifier):\(kind):\(result)"
    return EvidenceAppendOptions(
      context: workspace,
      idempotencyKey: idempotencyKey,
      target: EvidenceTarget(
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: nil,
        useCaseSemanticHash: semanticHash,
      ),
      kind: kind,
      result: result,
      summary: summary,
      actorType: performed == nil ? .agent : .script,
      hostSurface: hostSurface,
      method: performed.map { run in
        EvidenceObservationMethod(
          type: .structuredCommand,
          executable: run.argv.first,
          argv: run.argv,
        )
      },
    )
  }

  private static func append(_ options: EvidenceAppendOptions) async throws(CommandFailure)
    -> EvidenceAppendResult
  {
    do throws(EvidenceEventError) {
      return try await EvidenceAppender().append(options)
    } catch {
      throw CommandFailure(error)
    }
  }

  /// The legacy `assuranceClassMessage`, word for word.
  private static func assuranceClassMessage(_ assuranceClass: String) -> String {
    let note = switch assuranceClass {
    case "reported": " (self-reported — the weakest assurance tier)"
    case "observed": " (observed — stronger than self-reported)"
    case "reproducible": " (reproducible via a structured command — the strongest tier)"
    case "reference": " (reference link)"
    default: ""
    }
    return "Evidence assurance class: \(assuranceClass)\(note)."
  }

  private static func information(
    _ code: String,
    _ message: String,
  ) -> Diagnostic {
    Diagnostic(code: code, severity: .info, message: message)
  }
}
