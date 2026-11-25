/// A route that `record` offers for a use case, with the steps a person performs to prove it.
public struct RecordRouteOffer: Equatable, Sendable {
  /// The route's id.
  public let route: String

  /// The route's procedure steps; none when it has no procedure.
  public let steps: [String]

  /// Makes the offer of a route.
  public init(
    route: String,
    steps: [String],
  ) {
    self.route = route
    self.steps = steps
  }
}
