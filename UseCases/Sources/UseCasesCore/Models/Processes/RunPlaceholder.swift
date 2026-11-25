/// A word in braces in an argument of a run command: a brace pair holding one bare word, which is
/// a letter or underscore and then letters, digits or underscores, and that no `$` stands before
/// (chapter 10 §8). `{report}` is the one placeholder; a word that is a near miss of it is a
/// mistake the bridge check refuses; every other word in braces is plain text, as are a shell
/// brace group, `${HOME}`, `{ }`, `{a b}` and JSON, all passed on as written.
struct RunPlaceholder: Equatable, Sendable {
  /// The one placeholder the core knows.
  static let knownName = "report"

  /// The word between the braces.
  let name: String

  /// The braces and the word, where they stand in the argument.
  let range: Range<String.Index>

  /// Whether the core fills this placeholder in.
  var isKnown: Bool {
    name == Self.knownName
  }

  /// Whether the word is a near miss of the known placeholder, so most likely a mistyped one:
  /// the same word in other letter case, or one edit from it, a swap of two neighbouring letters
  /// counting as one, such as `{Report}`, `{reprot}`, `{reports}` or `{repot}`. Every other
  /// word, `{port}` and `{export}` among them, is plain text.
  var isNearMiss: Bool {
    guard !isKnown else {
      return false
    }

    return name.lowercased() == Self.knownName
      || Self.editDistance(from: name, to: Self.knownName) <= 1
  }

  /// The braces and the word as written, such as `{reprot}`.
  var text: String {
    ["{", name, "}"].joined()
  }

  /// Every placeholder in `argument`, in the order written.
  static func found(in argument: String) -> [RunPlaceholder] {
    let scalars = argument.unicodeScalars
    var found: [RunPlaceholder] = []
    var index = scalars.startIndex

    while index < scalars.endIndex {
      if let placeholder = placeholder(
        in: scalars,
        at: index,
      ) {
        found.append(placeholder)
        index = placeholder.range.upperBound
      } else {
        index = scalars.index(after: index)
      }
    }

    return found
  }

  private static func placeholder(
    in scalars: String.UnicodeScalarView,
    at open: String.Index,
  ) -> RunPlaceholder? {
    guard scalars[open] == "{" else {
      return nil
    }

    if open > scalars.startIndex, scalars[scalars.index(before: open)] == "$" {
      return nil
    }

    let start = scalars.index(after: open)
    var end = start

    while end < scalars.endIndex, isWordScalar(scalars[end], first: end == start) {
      end = scalars.index(after: end)
    }

    guard end > start, end < scalars.endIndex, scalars[end] == "}" else {
      return nil
    }

    return RunPlaceholder(
      name: String(scalars[start ..< end]),
      range: open ..< scalars.index(after: end),
    )
  }

  /// The fewest single-character insertions, deletions, substitutions and swaps of two
  /// neighbouring characters that turn `source` into `target`, no character being edited twice
  /// (the optimal string alignment distance).
  private static func editDistance(
    from source: String,
    to target: String,
  ) -> Int {
    let source = Array(source.unicodeScalars)
    let target = Array(target.unicodeScalars)
    var distance = (0 ... source.count).map { row in
      (0 ... target.count).map { column in
        row == 0 ? column : (column == 0 ? row : 0)
      }
    }

    for row in source.indices {
      for column in target.indices {
        var best = min(
          distance[row][column + 1] + 1,
          distance[row + 1][column] + 1,
          distance[row][column] + (source[row] == target[column] ? 0 : 1),
        )

        if row > 0, column > 0, source[row] == target[column - 1],
           source[row - 1] == target[column]
        {
          best = min(best, distance[row - 1][column - 1] + 1)
        }

        distance[row + 1][column + 1] = best
      }
    }

    return distance[source.count][target.count]
  }

  private static func isWordScalar(
    _ scalar: Unicode.Scalar,
    first: Bool,
  ) -> Bool {
    switch scalar {
    case "a" ... "z", "A" ... "Z", "_":
      true
    case "0" ... "9":
      !first
    default:
      false
    }
  }
}
