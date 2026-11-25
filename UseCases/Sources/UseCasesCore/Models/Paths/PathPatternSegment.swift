/// One segment of a path pattern: `**` for zero or more whole segments, or a name made of
/// literal characters, `*` and `?`.
enum PathPatternSegment: Hashable, Sendable {
  /// `**`: zero or more whole segments.
  case anyDepth

  /// A name to match in full.
  case name([Token])

  /// One piece of a name pattern.
  enum Token: Hashable, Sendable {
    /// A character that stands for itself, compared by Unicode scalar.
    case literal(Unicode.Scalar)

    /// `*`: any run of characters, within one segment.
    case anyRun

    /// `?`: exactly one character.
    case anyOne
  }

  /// Reads one segment of a pattern.
  init(
    parsing text: String,
    within pattern: String,
  ) throws(PathPatternError) {
    if text.isEmpty {
      throw .invalidPath(.empty)
    }

    if text == "**" {
      self = .anyDepth
      return
    }

    let scalars = Array(text.unicodeScalars)

    if zip(scalars, scalars.dropFirst()).contains(where: { $0 == "*" && $1 == "*" }) {
      throw .doubleStarNotWholeSegment(text, within: pattern)
    }

    self = .name(scalars.map(Token.init))
  }

  /// Whether a path segment fits this name pattern. `**` is not a name pattern, so it fits
  /// nothing here; the pattern as a whole decides how it spans segments.
  func matchesName(_ name: String) -> Bool {
    matchesName(scalars: Array(name.unicodeScalars))
  }

  /// The same, for a name already split into scalars.
  func matchesName(scalars: [Unicode.Scalar]) -> Bool {
    guard case let .name(tokens) = self else {
      return false
    }

    var reachable = [Bool](repeating: false, count: scalars.count + 1)
    reachable[0] = true

    for token in tokens {
      token.advance(
        &reachable,
        over: scalars,
      )
    }

    return reachable[scalars.count]
  }
}

private extension PathPatternSegment.Token {
  init(_ scalar: Unicode.Scalar) {
    switch scalar {
    case "*":
      self = .anyRun
    case "?":
      self = .anyOne
    default:
      self = .literal(scalar)
    }
  }

  /// Given which prefixes of `scalars` the earlier tokens can match, moves `reachable` on to the
  /// prefixes this token extends them to.
  func advance(
    _ reachable: inout [Bool],
    over scalars: [Unicode.Scalar],
  ) {
    switch self {
    case .anyRun:
      var seen = false
      for index in reachable.indices {
        seen = seen || reachable[index]
        reachable[index] = seen
      }
    case .anyOne:
      for index in scalars.indices.reversed() {
        reachable[index + 1] = reachable[index]
      }
      reachable[0] = false
    case let .literal(expected):
      for index in scalars.indices.reversed() {
        reachable[index + 1] = reachable[index] && scalars[index] == expected
      }
      reachable[0] = false
    }
  }
}
