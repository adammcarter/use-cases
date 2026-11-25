/// One route of one use case: what a route's history and every freshness collection are keyed by.
struct RouteKey: Hashable, Sendable {
  let useCase: UseCaseIdentifier
  let route: RouteIdentifier
}
