/// The line under a page of matches that says how many there are, for `search` and `docs`.
enum MatchCountLine {
  /// - Parameters:
  ///   - total: How many match in all.
  ///   - offset: How many come before this page.
  ///   - shown: How many this page holds.
  ///   - hasNext: Whether a page follows.
  static func text(
    total: Int,
    offset: Int,
    shown: Int,
    hasNext: Bool,
  ) -> String {
    guard total > 0 else {
      return "no matches"
    }

    guard offset > 0 || hasNext else {
      return total == 1 ? "1 match" : "\(total) matches"
    }

    let first = offset + 1
    let last = offset + shown
    let range = first == last ? "\(first)" : "\(first)–\(last)"

    return "\(range) of \(total) matches"
  }
}
