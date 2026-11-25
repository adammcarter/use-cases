/// One use case a proposal names, set against the workspace as it is.
struct ResolvedChange: Equatable, Sendable {
  /// The full id.
  let identifier: String

  let fit: ProposalFit

  /// The use case as the workspace holds it now; `nil` for a new one.
  let before: UseCaseDefinition?

  /// What is shown of it: the use case as the proposal leaves it, or as it was when it goes or
  /// stays.
  let shown: UseCaseDefinition
}
