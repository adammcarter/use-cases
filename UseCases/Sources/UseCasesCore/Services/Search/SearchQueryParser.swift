/// Splits typed words into words, phrases and words to leave out.
struct SearchQueryParser: SearchQueryParsing {
  func query(
    from text: String,
    isExact: Bool,
  ) throws(UseCaseSearchError) -> SearchQuery {
    var words: [String] = []
    var phrases: [[String]] = []
    var exclusions: [[String]] = []

    var rest = Substring(text)

    while let piece = try nextPiece(of: &rest) {
      let found = piece.text.searchWords

      guard !found.isEmpty else {
        continue
      }

      switch (piece.leavesOut, piece.isQuoted) {
      case (true, _):
        exclusions.append(found)
      case (false, true):
        phrases.append(found)
      case (false, false):
        words += found
      }
    }

    let query = SearchQuery(
      words: words,
      phrases: phrases,
      exclusions: exclusions,
      isExact: isExact,
    )

    guard !query.isEmpty else {
      throw .noWords
    }

    return query
  }

  /// The next word or quoted phrase, with a `-` before it when it leaves use cases out; `nil`
  /// when the text is used up.
  private func nextPiece(of rest: inout Substring) throws(UseCaseSearchError) -> Piece? {
    rest = rest.drop { character in
      character.isWhitespace
    }

    guard !rest.isEmpty else {
      return nil
    }

    let leavesOut = rest.first == "-"

    if leavesOut {
      rest = rest.dropFirst()
    }

    guard rest.first == "\"" else {
      let word = rest.prefix { character in
        !character.isWhitespace
      }
      rest = rest.dropFirst(word.count)

      return Piece(
        text: String(word),
        isQuoted: false,
        leavesOut: leavesOut,
      )
    }

    rest = rest.dropFirst()

    guard let end = rest.firstIndex(of: "\"") else {
      throw .unclosedQuote
    }

    let phrase = String(rest[..<end])
    rest = rest[rest.index(after: end)...]

    return Piece(
      text: phrase,
      isQuoted: true,
      leavesOut: leavesOut,
    )
  }

  private struct Piece {
    let text: String
    let isQuoted: Bool
    let leavesOut: Bool
  }
}
