/// One capsule run past its checks: the showcase run started, and every step,
/// item verdict and finish recorded under keys derived from one base key
/// (the body of `runDemoCapsule`).
struct DemoCapsulePerformance {
  let runner: DemoCapsuleRunner
  let options: DemoCapsuleRunOptions
  let plan: PresentationPlan
  let steps: [DemoCapsulePlannedStep]
  let baseKey: String
  let runIdentifier: String
  /// Only `recorded_at` is ever stamped, and every recording carries one, so
  /// the recorder's own clock is never read.
  let recorder = ShowcaseRecorder()
  private let workingDirectories: [String: String]
  private(set) var eventsWritten: [String] = []
  private(set) var pendingSteps: [DemoCapsulePendingStep] = []
  private(set) var commandResults: [DemoCapsuleCommandResult] = []

  /// Starts the run: script-led when the capsule has any command step.
  init(
    runner: DemoCapsuleRunner,
    options: DemoCapsuleRunOptions,
    plan: PresentationPlan,
    steps: [DemoCapsulePlannedStep],
    workingDirectories: [String],
  ) throws(DemoCapsuleError) {
    self.runner = runner
    self.options = options
    self.plan = plan
    self.steps = steps
    let commandSteps = steps.filter { $0.command != nil }
    var directories: [String: String] = [:]
    for (step, directory) in zip(commandSteps, workingDirectories) {
      directories[step.stepIdentifier] = directory
    }
    self.workingDirectories = directories
    baseKey = options.idempotencyKey
      ?? "capsule:\(options.capsuleIdentifier):\(JavaScriptNumber.text(runner.clock.now()))"

    let start: ShowcaseAppendResult
    do throws(ShowcaseError) {
      start = try recorder.start(
        plan: plan.jsonValue.objectValue ?? JSONObject(),
        controlMode: commandSteps.isEmpty ? .agentLed : .scriptLed,
        recording: Self.recording(options, options.actorType, "\(baseKey):start"),
      )
    } catch {
      throw .showcase(error)
    }
    runIdentifier = start.event["run_id"]?.stringValue ?? ""
    eventsWritten.append(Self.eventIdentifier(start))
  }

  /// Every step, then the item verdicts, then the finish when nothing is
  /// pending or failing.
  mutating func perform(
    capsule: DemoCapsule,
    planResult: PresentationPlanResult,
    diagnostics: [Diagnostic],
  ) throws(DemoCapsuleError) -> DemoCapsuleRunResult {
    for step in steps {
      try record(step)
    }
    let status: ShowcaseRunStatus
    do throws(ShowcaseError) {
      for item in capsule.items {
        try recordItemVerdict(item)
      }
      status = try finishedStatus()
    } catch {
      throw .showcase(error)
    }
    let isComplete = pendingSteps.isEmpty
      && status.executionStatus == "completed"
      && ["passed", "passed_with_waivers"].contains(status.runOutcome)
    return DemoCapsuleRunResult(
      outcome: .performed,
      isComplete: isComplete,
      capsuleIdentifier: options.capsuleIdentifier,
      runIdentifier: runIdentifier,
      eventsWritten: Self.firstOccurrences(eventsWritten),
      pendingSteps: pendingSteps,
      commandResults: commandResults,
      status: status,
      planResult: planResult,
      diagnostics: diagnostics,
    )
  }

  /// The run's status, after finishing it when nothing is pending or failing.
  private mutating func finishedStatus() throws(ShowcaseError) -> ShowcaseRunStatus {
    let status = try ShowcaseReplay.replay(context: options.context, runIdentifier: runIdentifier)
    guard pendingSteps.isEmpty, status.unresolvedFailureCount == 0 else {
      return status
    }
    let finish = try recorder.finish(
      runIdentifier: runIdentifier,
      recording: Self.recording(options, options.actorType, "\(baseKey):finish"),
    )
    eventsWritten.append(Self.eventIdentifier(finish))
    return finish.status
  }

  private mutating func record(_ entry: DemoCapsulePlannedStep) throws(DemoCapsuleError) {
    let stepIdentifier = entry.stepIdentifier
    switch entry.step {
    case let .instruction(text):
      try recordAction(
        entry,
        [("kind", .string("instruction")), ("text", .string(text))],
        actor: options.actorType,
        key: "\(baseKey):action:\(stepIdentifier)",
      )
    case let .observation(text):
      try recordAction(
        entry,
        [("kind", .string("expected_observation_prompt")), ("text", .string(text))],
        actor: options.actorType,
        key: "\(baseKey):expected-observation:\(stepIdentifier)",
      )
      pendingSteps.append(pending(entry, .runtimeObservationRequired))
    case let .command(command):
      guard options.isExecutingCommands else {
        pendingSteps.append(pending(entry, .commandExecutionNotRequested))
        return
      }
      try runCommand(command, entry)
    }
  }

  /// A command whose verdict is already on the ledger is not run again.
  private mutating func runCommand(
    _ command: DemoCapsuleCommandStep,
    _ entry: DemoCapsulePlannedStep,
  ) throws(DemoCapsuleError) {
    let stepIdentifier = entry.stepIdentifier
    guard let workingDirectory = workingDirectories[stepIdentifier] else {
      return
    }
    let verdictKey = "\(baseKey):command-verdict:\(stepIdentifier)"
    guard try !hasCommittedEvent(keyedBy: verdictKey) else {
      return
    }
    let result = try runner.execute(
      command,
      entry,
      workingDirectory: workingDirectory,
      options: options,
    )
    commandResults.append(result)
    try recordAction(
      entry,
      [
        ("kind", .string("command")),
        ("executable", .string(command.executable)),
        ("argv", .array(command.arguments.map(JSONValue.string))),
        ("working_directory", .string(command.workingDirectory)),
      ],
      actor: .script,
      key: "\(baseKey):command-action:\(stepIdentifier)",
    )
    do throws(ShowcaseError) {
      let observation = try recorder.recordObservation(
        runIdentifier: runIdentifier,
        planItemIdentifier: entry.planItemIdentifier,
        text: DemoCapsuleRunner.observationText(result),
        recording: Self.recording(
          options,
          .script,
          "\(baseKey):command-observation:\(stepIdentifier)",
        ),
      )
      eventsWritten.append(Self.eventIdentifier(observation))
      let verdict = try recorder.recordVerdict(
        runIdentifier: runIdentifier,
        planItemIdentifier: entry.planItemIdentifier,
        verdict: result.isExpectedExitCode ? .pass : .fail,
        observationEventIdentifiers: [Self.eventIdentifier(observation)],
        recording: Self.recording(options, .script, verdictKey),
      )
      eventsWritten.append(Self.eventIdentifier(verdict))
    } catch {
      throw .showcase(error)
    }
  }

  /// An item with nothing pending and no command run this time, whose plan
  /// item already has an observation, gets a pass verdict on it.
  private mutating func recordItemVerdict(_ item: DemoCapsuleItem) throws(ShowcaseError) {
    let useCase = item.useCaseIdentifier
    let hasPending = pendingSteps.contains { JavaScriptString.identical(
      $0.useCaseIdentifier,
      useCase,
    ) }
    let hasCommandVerdict = commandResults.contains { result in
      JavaScriptString.identical(result.useCaseIdentifier, useCase)
    }
    guard !hasPending, !hasCommandVerdict else {
      return
    }
    let status = try ShowcaseReplay.replay(context: options.context, runIdentifier: runIdentifier)
    let planItem = status.items.first { candidate in
      plan.selectedItems.contains { selected in
        candidate.planItemIdentifier == .string(selected.planItemIdentifier)
          && JavaScriptString.identical(selected.useCaseIdentifier, useCase)
      }
    }
    guard let planItemIdentifier = planItem?.planItemIdentifier?.stringValue,
          let observation = planItem?.latestObservationEventIdentifier?.stringValue,
          !observation.isEmpty
    else {
      return
    }
    let verdict = try recorder.recordVerdict(
      runIdentifier: runIdentifier,
      planItemIdentifier: planItemIdentifier,
      verdict: .pass,
      observationEventIdentifiers: [observation],
      recording: Self.recording(options, options.actorType, "\(baseKey):item-verdict:\(useCase)"),
    )
    eventsWritten.append(Self.eventIdentifier(verdict))
  }

  private mutating func recordAction(
    _ entry: DemoCapsulePlannedStep,
    _ members: [(String, JSONValue)],
    actor: ShowcaseActorType,
    key: String,
  ) throws(DemoCapsuleError) {
    do throws(ShowcaseError) {
      let result = try recorder.recordAction(
        runIdentifier: runIdentifier,
        planItemIdentifier: entry.planItemIdentifier,
        action: entry.action(members),
        recording: Self.recording(options, actor, key),
      )
      eventsWritten.append(Self.eventIdentifier(result))
    } catch {
      throw .showcase(error)
    }
  }

  private func hasCommittedEvent(keyedBy key: String) throws(DemoCapsuleError) -> Bool {
    do throws(ShowcaseError) {
      return try ShowcaseLedger.read(context: options.context, runIdentifier: runIdentifier).events
        .contains { event in
          guard let recorded = event["idempotency_key"]?.stringValue else {
            return false
          }
          return JavaScriptString.identical(recorded, key)
        }
    } catch {
      throw .showcase(error)
    }
  }

  private func pending(
    _ entry: DemoCapsulePlannedStep,
    _ reason: DemoCapsulePendingStep.Reason,
  ) -> DemoCapsulePendingStep {
    DemoCapsulePendingStep(
      itemIndex: entry.itemIndex,
      stepIndex: entry.stepIndex,
      useCaseIdentifier: entry.useCaseIdentifier,
      reason: reason,
    )
  }

  private static func recording(
    _ options: DemoCapsuleRunOptions,
    _ actor: ShowcaseActorType,
    _ key: String,
  ) -> ShowcaseRecording {
    ShowcaseRecording(
      context: options.context,
      actorType: actor,
      hostSurface: options.hostSurface,
      idempotencyKey: key,
      recordedAt: options.recordedAt,
    )
  }

  private static func eventIdentifier(_ result: ShowcaseAppendResult) -> String {
    result.event["event_id"]?.stringValue ?? ""
  }

  /// `[...new Set(values)]`.
  private static func firstOccurrences(_ values: [String]) -> [String] {
    var seen = Set<CodeUnitKey>()
    return values.filter { value in
      seen.insert(CodeUnitKey(value)).inserted
    }
  }
}
