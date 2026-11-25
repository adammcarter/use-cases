/// A route of a READY use case as the judge sees it (chapter 07 "How the core judges"): the keys
/// of its validation links, which are what the results are addressed by.
struct JudgedRoute: Equatable, Sendable {
  let key: RouteKey

  /// The keys of the route's validation links, in link order.
  let linkKeys: [String]

  /// Whether the route has a manual procedure.
  let hasProcedure: Bool
}
