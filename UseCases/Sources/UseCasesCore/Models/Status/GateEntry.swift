/// A use case the gate blocks on or warns about (chapter 16 §10).
public struct GateEntry: Equatable, Sendable {
  /// The full id.
  public let useCase: String

  /// The use case's verification state.
  public let status: VerificationStatus

  /// Why the gate holds it: its state when that blocks or warns, otherwise its sign-off.
  public let reason: GateReason

  /// `changed` or `unapproved` when the sign-off is what holds it; `nil` otherwise.
  public let heldForApproval: ApprovalState?
}
