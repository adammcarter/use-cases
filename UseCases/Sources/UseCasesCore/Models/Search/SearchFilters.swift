/// Which use cases a search keeps (chapter 16 §15): across the filters every one must hold, and
/// inside one filter any value may.
struct SearchFilters: Equatable, Sendable {
  /// An id prefix, or a use case id.
  let under: String?

  /// A group name.
  let group: String?

  /// Empty keeps every tier.
  let tiers: Set<ValueTier>

  /// Empty keeps every state.
  let states: Set<VerificationStatus>

  /// A use case that is never a result: the one `--like` was given.
  let excluded: String?
}
