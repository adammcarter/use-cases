/// How well a use case, or a section, matches a query: where, and how much.
struct TextMatch: Equatable, Sendable {
  /// What the best possible match to one word is: a field of the highest weight, matched exactly.
  static let bestWeight = 10
  static let exactQuality = 100
  static let bestPoints = bestWeight * exactQuality

  /// The most a score can be, as a whole number: scores are worked out in ten-thousandths so
  /// that no system rounds differently.
  static let bestScore = 10000

  /// The passages that matched, the strongest first, ties in the order given.
  let hits: [PassageHit]

  /// The best match of each word and phrase, added up.
  let points: Int

  /// How many words and phrases the query has.
  let termCount: Int

  /// From 1 to ``bestScore``: the points over the most the query could have scored, worked out
  /// with whole numbers and rounded to the nearest ten-thousandth. Never 0, because a match
  /// always scores.
  var score: Int {
    let most = termCount * Self.bestPoints

    guard most > 0 else {
      return 1
    }

    return max(1, (points * Self.bestScore + most / 2) / most)
  }
}

/// One passage that matched, and how strongly.
struct PassageHit: Equatable, Sendable {
  /// Where the passage is in the list that was searched.
  let index: Int

  /// The weight of the passage times the quality of each word and phrase that matched in it,
  /// added up.
  let strength: Int
}
