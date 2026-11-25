/// How big a file may get before it is refused rather than read.
struct YAMLReadingLimits: Equatable, Sendable {
  /// The limits every authored file is read under.
  static let standard = YAMLReadingLimits(
    nesting: 64,
    values: 100_000,
  )

  /// How many lists and mappings may sit inside one another.
  let nesting: Int

  /// How many values a file may read as: every scalar, list and mapping, keys included, with
  /// aliases expanded.
  let values: Int
}
