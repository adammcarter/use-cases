/// Why the gate holds a use case.
public enum GateReason: Equatable, Sendable {
  /// Its verification state.
  case status(VerificationStatus)

  /// Its promise is not approved as it reads now, and the root requires sign-off.
  case notApproved
}
