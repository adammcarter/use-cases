/// Runs a capsule's command step: the process externality behind
/// `runDemoCapsule`.
public protocol CapsuleCommandSpawning: Sendable {
  func spawn(_ request: CapsuleSpawnRequest) throws(CapsuleSpawnError) -> CapsuleSpawnOutcome
}
