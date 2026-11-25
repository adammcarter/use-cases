/// What judging a route came to: a verdict, or the reason it has none.
enum RouteOutcome: Equatable, Sendable {
  case verdict(RouteVerdict)

  /// The route has no validation link and no procedure, so no test could ever speak for it.
  case notLinked

  /// A validation link got no result and none failed: "its test didn't run". `links` are the
  /// keys that got none.
  case didntRun(links: [String])
}
