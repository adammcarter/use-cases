/// The repository-wide settings only the root scope holds, with their defaults filled in
/// (chapter 04, chapter 09 §8 and §23). A child scope has none, so a child's configuration
/// cannot represent one.
struct RootSettings: Equatable, Sendable {
  let freshness: FreshnessPolicy

  /// `discovery.exclude`, in the order written. The built-in exclusions (chapter 04 "Discovery
  /// exclusions") are not part of it.
  let discoveryExclusions: [PathPattern]

  /// The sign-off gate, when the root turns it on.
  let signOff: SignOffRequirement?

  /// What a root that writes none of them means.
  static let standard = RootSettings(
    freshness: .standard,
    discoveryExclusions: [],
    signOff: nil,
  )
}
