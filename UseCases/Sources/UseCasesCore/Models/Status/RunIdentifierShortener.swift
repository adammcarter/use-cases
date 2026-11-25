/// Shows a run id to a person (chapter 16 §9): the shortest prefix of at least 8 digits that names
/// only one run in the store, as git shortens a commit. Run ids start with the time, so runs
/// started close together share their first digits and need more than 8.
public struct RunIdentifierShortener: Equatable, Sendable {
  /// The fewest digits shown.
  static let minimumLength = 8

  private let lengths: [String: Int]

  /// - Parameter runs: The whole id of every run in the store, in any order.
  public init(runs: [String]) {
    let ordered = Array(Set(runs)).sorted()
    var lengths: [String: Int] = [:]

    for (index, run) in ordered.enumerated() {
      var shared = 0

      if index > 0 {
        shared = max(shared, Self.commonPrefixLength(run, ordered[index - 1]))
      }
      if index + 1 < ordered.count {
        shared = max(shared, Self.commonPrefixLength(run, ordered[index + 1]))
      }

      lengths[run] = max(Self.minimumLength, shared + 1)
    }

    self.lengths = lengths
  }

  /// The run id as a person sees it. A run the store does not hold shows its first 8 digits.
  public func shortened(_ run: String) -> String {
    String(run.prefix(lengths[run] ?? Self.minimumLength))
  }

  private static func commonPrefixLength(
    _ first: String,
    _ second: String,
  ) -> Int {
    zip(first, second).prefix { pair in
      pair.0 == pair.1
    }.count
  }
}
