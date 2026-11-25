/// The verdict the core judged for one route of a verify run (chapter 07, chapter 13 §9).
struct RouteVerdict: Equatable, Sendable {
  let key: RouteKey
  let verdict: Verdict

  /// Every validation link of the route with the worst result it received, `nil` when none.
  let links: [LinkResult]

  /// The validations whose reports gave a result to a link of the route, in the order of the
  /// bridge settings.
  let via: [IdentifierSegment]
}
