/// One check behind a saved use case: a route that gates, by its id.
public struct ResultCheck: Equatable, Sendable {
  /// The route's id.
  public let label: String

  public let status: VerificationStatus

  /// A check.
  public init(
    label: String,
    status: VerificationStatus,
  ) {
    self.label = label
    self.status = status
  }
}
