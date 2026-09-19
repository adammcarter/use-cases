/// How planning a capsule ended (`CapsulePlanResult["outcome"]`).
public enum CapsulePlanOutcome: String, Sendable, Equatable {
  case generated
  case capsuleNotFound = "capsule_not_found"
  case integrityBlocked = "integrity_blocked"
}
