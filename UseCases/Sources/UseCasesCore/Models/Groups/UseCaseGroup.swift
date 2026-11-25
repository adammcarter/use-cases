/// A group once its selectors are resolved against the use cases of the workspace (chapter 03):
/// an unordered set, derived from the current use cases and never written back.
struct UseCaseGroup: Equatable, Sendable {
  let name: IdentifierSegment
  let description: String?

  /// The full ids of the members, sorted.
  let members: [String]
}
