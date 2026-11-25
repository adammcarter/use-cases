/// One validation route of a READY use case, judged against its current fingerprint (chapter 07
/// "Route verification status").
public struct RouteStatus: Equatable, Sendable {
  /// The route's id within its use case.
  public let identifier: String

  /// Whether the route counts towards the use case's status (`gates_verification`).
  public let gates: Bool

  /// Whether the route has a procedure or validation links, so something can reach it.
  public let isLinked: Bool

  /// One of the six verification states; never `draft`.
  public let status: VerificationStatus

  public let explanation: RouteExplanation
}
