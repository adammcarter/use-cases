/// A runbook step a run left for someone else (`DemoCapsulePendingStep`).
public struct DemoCapsulePendingStep: Sendable, Equatable {
  /// Why the step is still open.
  public enum Reason: String, Sendable, Equatable {
    case commandExecutionNotRequested = "command_execution_not_requested"
    case runtimeObservationRequired = "runtime_observation_required"
  }

  public let itemIndex: Int
  public let stepIndex: Int
  public let useCaseIdentifier: String
  public let reason: Reason

  public init(
    itemIndex: Int,
    stepIndex: Int,
    useCaseIdentifier: String,
    reason: Reason,
  ) {
    self.itemIndex = itemIndex
    self.stepIndex = stepIndex
    self.useCaseIdentifier = useCaseIdentifier
    self.reason = reason
  }

  /// `{ item_index, step_index, use_case_id, reason }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("item_index", .number(Double(itemIndex))),
      ("step_index", .number(Double(stepIndex))),
      ("use_case_id", .string(useCaseIdentifier)),
      ("reason", .string(reason.rawValue)),
    ]))
  }
}
