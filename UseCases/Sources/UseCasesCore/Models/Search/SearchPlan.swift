/// A search that is understood: what to look for, where, which use cases, and which page. It is
/// all the following page needs, so it is what a `--next` token carries.
public struct SearchPlan: Equatable, Sendable {
  let query: SearchQuery
  let filters: SearchFilters

  /// The fields searched, in the order of ``SearchField/allCases``.
  let fields: [SearchField]

  let wantsFull: Bool
  let pageSize: Int
  let offset: Int

  /// The seal of the token this plan was read from; `nil` for a new search. It says the plan is
  /// as the search made it and the use cases are as the search saw them.
  let seal: String?
}
