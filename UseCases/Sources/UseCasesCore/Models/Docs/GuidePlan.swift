/// A search of the guides that is understood: what to look for and which page. It is all the
/// following page needs, so it is what a `--next` token carries.
public struct GuidePlan: Equatable, Sendable {
  let query: SearchQuery
  let pageSize: Int
  let offset: Int

  /// The seal of the token this plan was read from; `nil` for a new search. It says the plan is
  /// as the search made it and the guides are as the search saw them.
  let seal: String?
}
