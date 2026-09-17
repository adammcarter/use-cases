/// Whether a capsule run got as far as starting a showcase run
/// (`DemoCapsuleRunResult["outcome"]`).
public enum DemoCapsuleRunOutcome: String, Sendable, Equatable {
  case performed
  case blocked
}
