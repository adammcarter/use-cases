/// The exclusion pattern that covers a path, and where it came from.
struct ExclusionMatch: Equatable, Sendable {
  /// The pattern as written.
  let pattern: String

  /// Whether it is one of the default exclusions rather than the root's `discovery.exclude`.
  let isBuiltIn: Bool

  /// How a message names the pattern.
  var subject: String {
    isBuiltIn ? "the built-in exclusion '\(pattern)'" : "discovery.exclude '\(pattern)'"
  }
}
