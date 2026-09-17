/// The members of a schema-valid capsule that planning and running read
/// (`DemoCapsule`). The capsule's JSON itself travels in
/// ``LoadedDemoCapsule/capsule``, as parsed.
public struct DemoCapsule: Sendable, Equatable {
  public let capsuleIdentifier: String
  public let mode: PresentationMode
  public let audience: String
  public let timeboxSeconds: Double
  public let items: [DemoCapsuleItem]
  public let isCommandExecutionPermitted: Bool

  /// The capsule a value describes, or nil when it is not a schema-valid
  /// capsule.
  public init?(_ value: JSONValue) {
    guard let capsuleIdentifier = value["capsule_id"]?.stringValue,
          let mode = value["mode"]?.stringValue.flatMap(PresentationMode.init(rawValue:)),
          let audience = value["audience"]?.stringValue,
          let timeboxSeconds = value["timebox_seconds"]?.numberValue,
          let items = value["items"]?.arrayValue,
          let isPermitted = value["permissions"]?["command_execution"]?.boolValue
    else {
      return nil
    }
    var parsedItems: [DemoCapsuleItem] = []
    for item in items {
      guard let useCaseIdentifier = item["use_case_id"]?.stringValue,
            let runbook = item["runbook"]?.arrayValue
      else {
        return nil
      }
      let steps = runbook.compactMap(DemoCapsuleRunbookStep.init)
      guard steps.count == runbook.count else {
        return nil
      }
      parsedItems.append(DemoCapsuleItem(useCaseIdentifier: useCaseIdentifier, runbook: steps))
    }
    self.capsuleIdentifier = capsuleIdentifier
    self.mode = mode
    self.audience = audience
    self.timeboxSeconds = timeboxSeconds
    self.items = parsedItems
    isCommandExecutionPermitted = isPermitted
  }
}
