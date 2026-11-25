/// A path pattern in the one dialect every authored pattern uses (chapter 04): `*` within a
/// segment, `?` for one character, `**` as a whole segment for zero or more segments, and
/// everything else literal. Matching is case-sensitive and exact in Unicode form.
struct PathPattern: PathPatternMatching, Hashable, Sendable, CustomStringConvertible {
  /// The pattern as written, kept for messages.
  let text: String

  /// The segments to match. A run of `**` is one segment here: `**/**` means what `**` means.
  let segments: [PathPatternSegment]

  /// Reads a pattern, refusing what is not workspace-relative and canonically spelled with `/`
  /// separators (`/x`, `..`, `\`, `./x`, `a//b`, `a/`, `.`), and `**` inside a longer segment
  /// (`a**`).
  init(validating text: String) throws(PathPatternError) {
    do {
      try WorkspacePath.checkRules(of: text)
    } catch {
      // A pattern naming the workspace root would exclude everything, so `.` is no spelling to
      // suggest for one.
      if case let .notCanonical(refused, canonical: "."?) = error {
        throw .invalidPath(.notCanonical(refused, canonical: nil))
      }

      throw .invalidPath(error)
    }

    if text == "." {
      throw .invalidPath(.notCanonical(text, canonical: nil))
    }

    var parsed: [PathPatternSegment] = []

    for piece in text.splitOnScalar("/") {
      let segment = try PathPatternSegment(
        parsing: piece,
        within: text,
      )

      if segment == .anyDepth, parsed.last == .anyDepth {
        continue
      }

      parsed.append(segment)
    }

    self.text = text
    segments = parsed
  }

  var description: String {
    text
  }

  static func == (
    lhs: PathPattern,
    rhs: PathPattern,
  ) -> Bool {
    lhs.segments == rhs.segments
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(segments)
  }

  func matches(_ path: WorkspacePath) -> Bool {
    let names = path.segments
    return matchedPrefixLengths(of: names).contains(names.count)
  }

  func excludes(_ path: WorkspacePath) -> Bool {
    !matchedPrefixLengths(of: path.segments).isEmpty
  }

  /// The lengths, from 1, of the leading part of `names` that the whole pattern matches.
  private func matchedPrefixLengths(of names: [String]) -> Set<Int> {
    var lengths: Set<Int> = []
    var states = closure(of: [0])

    for (index, name) in names.enumerated() {
      let scalars = Array(name.unicodeScalars)
      var next: Set<Int> = []

      for state in states where state < segments.count {
        switch segments[state] {
        case .anyDepth:
          next.insert(state)
        case .name:
          if segments[state].matchesName(scalars: scalars) {
            next.insert(state + 1)
          }
        }
      }

      states = closure(of: next)

      if states.contains(segments.count) {
        lengths.insert(index + 1)
      }
    }

    return lengths
  }

  /// Adds the states reached by letting a `**` take no segment at all. `**` never follows `**`
  /// in `segments`, so one step is enough.
  private func closure(of states: Set<Int>) -> Set<Int> {
    var result = states

    for state in states where state < segments.count && segments[state] == .anyDepth {
      result.insert(state + 1)
    }

    return result
  }
}
