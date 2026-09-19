/// One use case a capsule presents, and the runbook for it
/// (`DemoCapsuleItem`).
public struct DemoCapsuleItem: Sendable, Equatable {
  public let useCaseIdentifier: String
  public let runbook: [DemoCapsuleRunbookStep]

  public init(
    useCaseIdentifier: String,
    runbook: [DemoCapsuleRunbookStep],
  ) {
    self.useCaseIdentifier = useCaseIdentifier
    self.runbook = runbook
  }
}
