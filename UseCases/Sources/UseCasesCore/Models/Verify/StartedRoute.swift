/// A route and its fingerprint at the start point of a verify run (chapter 12 §11).
struct StartedRoute: Equatable, Sendable {
  let useCase: UseCaseIdentifier
  let route: RouteIdentifier
  let fingerprint: RouteFingerprint

  var key: RouteKey {
    RouteKey(
      useCase: useCase,
      route: route,
    )
  }
}
