/// One group as written in `use-case-groups.yml` (chapter 03), before its selectors are resolved.
struct GroupDefinition: Equatable, Sendable {
  let name: IdentifierSegment

  /// Human-facing only: it affects neither membership nor freshness.
  let description: String?

  /// `nil` when the group does not write `include`, which means every use case.
  let include: GroupSelectors?

  /// `nil` when the group does not write `exclude`.
  let exclude: GroupSelectors?
}
