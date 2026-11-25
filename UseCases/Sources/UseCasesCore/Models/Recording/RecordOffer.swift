/// A READY use case that `record` offers, with its routes in the order they are written
/// (chapter 16 §12).
public struct RecordOffer: Equatable, Sendable {
  /// The use case's full id.
  public let useCase: String

  /// Its routes.
  public let routes: [RecordRouteOffer]

  /// Makes the offer of a use case.
  public init(
    useCase: String,
    routes: [RecordRouteOffer],
  ) {
    self.useCase = useCase
    self.routes = routes
  }
}
