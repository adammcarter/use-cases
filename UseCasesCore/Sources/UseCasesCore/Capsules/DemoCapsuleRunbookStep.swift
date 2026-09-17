/// One step of a capsule item's runbook (`DemoCapsuleRunbookStep`).
public enum DemoCapsuleRunbookStep: Sendable, Equatable {
  /// Something the presenter does.
  case instruction(text: String)
  /// Something the presenter must see happen.
  case observation(text: String)
  /// A program the runner may execute.
  case command(DemoCapsuleCommandStep)

  /// The step a schema-valid runbook entry describes, or nil for anything
  /// else.
  init?(_ value: JSONValue) {
    switch value["kind"]?.stringValue {
    case "instruction":
      guard let text = value["text"]?.stringValue else {
        return nil
      }
      self = .instruction(text: text)
    case "observation":
      guard let text = value["text"]?.stringValue else {
        return nil
      }
      self = .observation(text: text)
    case "command":
      guard let executable = value["executable"]?.stringValue,
            let arguments = value["argv"]?.arrayValue,
            let workingDirectory = value["working_directory"]?.stringValue,
            let codes = value["expected_exit_codes"]?.arrayValue
      else {
        return nil
      }
      self = .command(DemoCapsuleCommandStep(
        executable: executable,
        arguments: arguments.compactMap(\.stringValue),
        workingDirectory: workingDirectory,
        expectedExitCodes: codes.compactMap(\.numberValue),
      ))
    default:
      return nil
    }
  }
}
