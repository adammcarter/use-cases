/// A glob over whole id segments (chapter 03): `*` is exactly one segment and `**` is zero or
/// more, so `app.checkout.**` also matches `app.checkout` itself. Part of a segment is never
/// matched: `app.log*` is not a glob.
struct IdentifierGlob: Hashable, Sendable, CustomStringConvertible {
  /// One piece of a glob.
  enum Segment: Hashable, Sendable {
    /// `*`: exactly one whole segment.
    case anyOne

    /// `**`: zero or more whole segments.
    case anyDepth

    /// A segment that stands for itself.
    case named(IdentifierSegment)
  }

  /// The pieces in order, a run of `**` merged into one. Never empty.
  let segments: [Segment]

  /// The glob as it was written.
  let text: String

  /// Reads a glob, refusing an empty piece and anything off the segment grammar.
  init(validating text: String) throws(IdentityError) {
    guard !text.isEmpty else {
      throw .empty
    }

    var parsed: [Segment] = []

    for piece in text.splitOnScalar(".") {
      if piece.isEmpty {
        throw .emptySegment(within: text)
      }

      switch piece {
      case "*":
        parsed.append(.anyOne)
      case "**":
        // `**.**` says what `**` says; merged, a glob costs no more to match than its length.
        if parsed.last != .anyDepth {
          parsed.append(.anyDepth)
        }
      default:
        do {
          try parsed.append(.named(IdentifierSegment(validating: piece)))
        } catch {
          throw error.naming(wholeText: text)
        }
      }
    }

    segments = parsed
    self.text = text
  }

  var description: String {
    text
  }

  /// Whether the whole id fits the glob.
  ///
  /// Works along the pattern with one row of "the first `n` segments of the id are matched so
  /// far", so the time is the glob's length times the id's, however many `**` it holds and
  /// without recursion.
  func matches(_ identifier: UseCaseIdentifier) -> Bool {
    let subject = identifier.namespace.segments
    var matched = [Bool](repeating: false, count: subject.count + 1)
    matched[0] = true

    for segment in segments {
      switch segment {
      case .anyDepth:
        var reached = false

        for position in matched.indices {
          reached = reached || matched[position]
          matched[position] = reached
        }
      case .anyOne:
        matched = Self.shifted(matched) { _ in
          true
        }
      case let .named(name):
        matched = Self.shifted(matched) { position in
          subject[position] == name
        }
      }
    }

    return matched[subject.count]
  }

  /// The row after one more segment of the id is taken by a piece of the glob that fits it.
  private static func shifted(
    _ matched: [Bool],
    where fits: (Int) -> Bool,
  ) -> [Bool] {
    var next = [Bool](repeating: false, count: matched.count)

    for position in 1 ..< matched.count where matched[position - 1] && fits(position - 1) {
      next[position] = true
    }

    return next
  }
}
