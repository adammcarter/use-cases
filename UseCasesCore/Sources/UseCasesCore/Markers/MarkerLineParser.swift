/// The marker-line parser (spec section 1: grammar 1.2, slug rules 1.3).
///
/// A line is a marker only if, after optional `[ \t]` indentation, it begins
/// with exactly `<prefix>: @use-case:`. Once that token matches, the payload
/// MUST be a bare slug, `begin <slug>`, `end <slug>`, `ignore:begin` or
/// `ignore:end`; anything else is invalid. The comparison is per UTF-16 code
/// unit, as in the TypeScript — a combining mark after the colon is not folded
/// into it.
public enum MarkerLineParser {
  private static let beginKeyword = Array("begin".utf16)
  private static let endKeyword = Array("end".utf16)
  private static let ignoreBegin = Array("ignore:begin".utf16)
  private static let ignoreEnd = Array("ignore:end".utf16)

  public static func parse(
    _ line: String,
    commentPrefix: String,
  ) -> MarkerLineParse {
    let units = Array(line.utf16)
    let indent = CodeUnits.spaceOrTabRun(units, from: 0)
    let column = indent + 1
    let token = Array("\(commentPrefix): @use-case:".utf16)
    guard CodeUnits.hasPrefix(units, token, at: indent) else {
      return .none
    }

    let tokens = payloadTokens(Array(units[(indent + token.count)...]))
    guard let first = tokens.first else {
      return .invalid(
        code: .malformedMarker,
        message: "use-case marker has an empty payload",
        column: column,
        slug: nil,
      )
    }
    if first.contains(CodeUnits.colon) {
      return parseBlockPath(tokens, column: column)
    }
    if first == beginKeyword {
      return parseBegin(tokens, column: column)
    }
    if first == endKeyword {
      return parseEnd(tokens, column: column)
    }
    return parseStart(tokens, column: column)
  }

  /// The payload trimmed of `[ \t]` and split on runs of it.
  private static func payloadTokens(_ payload: [UInt16]) -> [[UInt16]] {
    payload
      .split(whereSeparator: CodeUnits.isSpaceOrTab)
      .map(Array.init)
  }

  private static func text(_ tokens: ArraySlice<[UInt16]>) -> String {
    tokens.map(CodeUnits.string).joined(separator: " ")
  }

  private static func parseBlockPath(
    _ tokens: [[UInt16]],
    column: Int,
  ) -> MarkerLineParse {
    let first = tokens[0]
    guard first == ignoreBegin || first == ignoreEnd else {
      return .invalid(
        code: .malformedMarker,
        message: "unknown block path",
        column: column,
        slug: CodeUnits.string(first),
      )
    }
    guard tokens.count == 1 else {
      return .invalid(
        code: .forbiddenMarkerPayload,
        message: "\(CodeUnits.string(first)) marker takes no payload",
        column: column,
        slug: nil,
      )
    }
    return first == ignoreBegin ? .ignoreBegin(column: column) : .ignoreEnd(column: column)
  }

  private static func parseBegin(
    _ tokens: [[UInt16]],
    column: Int,
  ) -> MarkerLineParse {
    guard tokens.count > 1 else {
      return .invalid(
        code: .malformedMarker,
        message: "begin marker has no slug; expected `begin <slug>`",
        column: column,
        slug: nil,
      )
    }
    let slug = CodeUnits.string(tokens[1])
    guard tokens.count == 2 else {
      return .invalid(
        code: .forbiddenMarkerPayload,
        message: "forbidden payload after begin slug: \(text(tokens[2...]))",
        column: column,
        slug: slug,
      )
    }
    guard MarkerSlug.isValid(slug) else {
      return .invalid(
        code: .malformedMarker,
        message: "invalid slug in begin marker: \(slug)",
        column: column,
        slug: slug,
      )
    }
    return .start(slug: slug, explicit: true, column: column)
  }

  private static func parseEnd(
    _ tokens: [[UInt16]],
    column: Int,
  ) -> MarkerLineParse {
    guard tokens.count > 1 else {
      return .invalid(
        code: .malformedEndMarker,
        message: "end marker has no slug; expected `end <slug>`",
        column: column,
        slug: nil,
      )
    }
    let slug = CodeUnits.string(tokens[1])
    guard tokens.count == 2 else {
      return .invalid(
        code: .forbiddenMarkerPayload,
        message: "forbidden payload after end slug: \(text(tokens[2...]))",
        column: column,
        slug: slug,
      )
    }
    guard MarkerSlug.isValid(slug) else {
      return .invalid(
        code: .malformedMarker,
        message: "invalid slug in end marker: \(slug)",
        column: column,
        slug: slug,
      )
    }
    return .end(slug: slug, column: column)
  }

  private static func parseStart(
    _ tokens: [[UInt16]],
    column: Int,
  ) -> MarkerLineParse {
    let slug = CodeUnits.string(tokens[0])
    guard tokens.count == 1 else {
      return .invalid(
        code: .forbiddenMarkerPayload,
        message: "forbidden payload after slug: \(text(tokens[1...]))",
        column: column,
        slug: slug,
      )
    }
    guard MarkerSlug.isValid(slug) else {
      return .invalid(
        code: .malformedMarker,
        message: "invalid slug: \(slug)",
        column: column,
        slug: slug,
      )
    }
    return .start(slug: slug, explicit: false, column: column)
  }
}
