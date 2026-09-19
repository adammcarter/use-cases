/// What running a capsule did (`DemoCapsuleRunResult`).
public struct DemoCapsuleRunResult: Sendable, Equatable {
  public let outcome: DemoCapsuleRunOutcome
  /// Nothing is pending and the run finished passed, or passed with waivers.
  public let isComplete: Bool
  public let capsuleIdentifier: String
  /// Nil when blocked.
  public let runIdentifier: String?
  /// The events this call appended or found under its idempotency keys, first
  /// occurrence order.
  public let eventsWritten: [String]
  public let pendingSteps: [DemoCapsulePendingStep]
  public let commandResults: [DemoCapsuleCommandResult]
  /// Nil when blocked.
  public let status: ShowcaseRunStatus?
  public let planResult: PresentationPlanResult?
  public let diagnostics: [Diagnostic]

  public init(
    outcome: DemoCapsuleRunOutcome,
    isComplete: Bool,
    capsuleIdentifier: String,
    runIdentifier: String?,
    eventsWritten: [String],
    pendingSteps: [DemoCapsulePendingStep],
    commandResults: [DemoCapsuleCommandResult],
    status: ShowcaseRunStatus?,
    planResult: PresentationPlanResult?,
    diagnostics: [Diagnostic],
  ) {
    self.outcome = outcome
    self.isComplete = isComplete
    self.capsuleIdentifier = capsuleIdentifier
    self.runIdentifier = runIdentifier
    self.eventsWritten = eventsWritten
    self.pendingSteps = pendingSteps
    self.commandResults = commandResults
    self.status = status
    self.planResult = planResult
    self.diagnostics = diagnostics
  }

  /// `blocked(...)`: nothing ran and nothing was written.
  static func blocked(
    capsuleIdentifier: String,
    planResult: PresentationPlanResult?,
    diagnostics: [Diagnostic],
  ) -> DemoCapsuleRunResult {
    DemoCapsuleRunResult(
      outcome: .blocked,
      isComplete: false,
      capsuleIdentifier: capsuleIdentifier,
      runIdentifier: nil,
      eventsWritten: [],
      pendingSteps: [],
      commandResults: [],
      status: nil,
      planResult: planResult,
      diagnostics: diagnostics,
    )
  }

  /// The TypeScript's result object, members in its order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("outcome", .string(outcome.rawValue)),
      ("complete", .bool(isComplete)),
      ("capsule_id", .string(capsuleIdentifier)),
      ("run_id", runIdentifier.map(JSONValue.string) ?? .null),
      ("events_written", .array(eventsWritten.map(JSONValue.string))),
      ("pending_steps", .array(pendingSteps.map(\.jsonValue))),
      ("command_results", .array(commandResults.map(\.jsonValue))),
      ("status", status?.jsonValue ?? .null),
      ("plan_result", planResult?.jsonValue ?? .null),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
