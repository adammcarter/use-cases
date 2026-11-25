/// What `approve` did to one use case (chapter 16 §14).
public enum ApprovalAction: String, Equatable, Sendable {
  /// Its promise as it reads now was approved, and the sign-off recorded.
  case approved

  /// It was already approved as it reads now: nothing is written.
  case unchanged
}
