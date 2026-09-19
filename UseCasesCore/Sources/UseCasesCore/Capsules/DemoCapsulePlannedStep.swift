/// One runbook step bound to the plan item it belongs to
/// (`PlannedCapsuleStep`), and — for a command about to run — the working
/// directory it resolved to.
struct DemoCapsulePlannedStep: Sendable {
  let itemIndex: Int
  let stepIndex: Int
  let useCaseIdentifier: String
  let planItemIdentifier: String
  let step: DemoCapsuleRunbookStep

  /// `<item>.<step>`, the suffix of every idempotency key the step records.
  var stepIdentifier: String {
    "\(itemIndex).\(stepIndex)"
  }

  /// The step's command, when it is one.
  var command: DemoCapsuleCommandStep? {
    guard case let .command(command) = step else {
      return nil
    }
    return command
  }

  /// `{ source: "demo_capsule", item_index, step_index }`, after `members`.
  func action(_ members: [(String, JSONValue)]) -> JSONObject {
    JSONObject(members + [
      ("source", .string("demo_capsule")),
      ("item_index", .number(Double(itemIndex))),
      ("step_index", .number(Double(stepIndex))),
    ])
  }
}
