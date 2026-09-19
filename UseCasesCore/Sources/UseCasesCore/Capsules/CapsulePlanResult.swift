/// A capsule's presentation plan, or why there is none
/// (`CapsulePlanResult`).
public struct CapsulePlanResult: Sendable, Equatable {
  public let outcome: CapsulePlanOutcome
  /// The capsule asked for, when it loaded — even when integrity blocked it.
  public let capsule: LoadedDemoCapsule?
  public let planResult: PresentationPlanResult?
  public let diagnostics: [Diagnostic]

  public init(
    outcome: CapsulePlanOutcome,
    capsule: LoadedDemoCapsule?,
    planResult: PresentationPlanResult?,
    diagnostics: [Diagnostic],
  ) {
    self.outcome = outcome
    self.capsule = capsule
    self.planResult = planResult
    self.diagnostics = diagnostics
  }

  /// `{ schema_version, outcome, capsule, plan_result, diagnostics }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("outcome", .string(outcome.rawValue)),
      ("capsule", capsule?.jsonValue ?? .null),
      ("plan_result", planResult?.jsonValue ?? .null),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
