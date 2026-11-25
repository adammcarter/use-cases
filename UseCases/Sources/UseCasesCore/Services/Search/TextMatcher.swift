/// Matches the words of a query to the words of passages, ranking an exact word above a word
/// start above a typo, and a heavier passage above a lighter one.
///
/// The score is worked out with whole numbers alone, so every system gives the same answer.
struct TextMatcher: TextMatching {
  /// What a word as typed is worth against a word it starts, and against a typo of it.
  static let wordStartQuality = 70
  static let oneTypoQuality = 45
  static let twoTyposQuality = 30

  /// A word start counts for a query word of this many letters or more.
  static let shortestWordStart = 3

  private let distance: WordDistance

  init(distance: WordDistance = WordDistance()) {
    self.distance = distance
  }

  func match(
    _ query: SearchQuery,
    in passages: [SearchPassage],
  ) -> TextMatch? {
    guard !leavesOut(query, passages) else {
      return nil
    }

    var total = 0
    var totals = [Int](repeating: 0, count: passages.count)
    var anyWordMatched = false

    for word in query.words {
      let found = perPassage(
        ofWord: word,
        in: passages,
        isExact: query.isExact,
      )
      let best = found.max() ?? 0

      anyWordMatched = anyWordMatched || best > 0
      total += best
      totals = zip(totals, found).map(+)
    }

    for phrase in query.phrases {
      let found = passages.map { passage in
        Self.contains(
          phrase,
          in: passage.words,
        ) ? passage.weight * TextMatch.exactQuality : 0
      }
      let best = found.max() ?? 0

      guard best > 0 else {
        return nil
      }

      total += best
      totals = zip(totals, found).map(+)
    }

    guard query.words.isEmpty || anyWordMatched else {
      return nil
    }

    return TextMatch(
      hits: Self.hits(of: totals),
      points: total,
      termCount: query.termCount,
    )
  }

  /// Whether a word or phrase to leave out is in any passage, as whole words.
  private func leavesOut(
    _ query: SearchQuery,
    _ passages: [SearchPassage],
  ) -> Bool {
    query.exclusions.contains { exclusion in
      passages.contains { passage in
        Self.contains(
          exclusion,
          in: passage.words,
        )
      }
    }
  }

  /// What each passage is worth for one query word: its weight times how well the word matches
  /// its best word, or 0.
  private func perPassage(
    ofWord word: String,
    in passages: [SearchPassage],
    isExact: Bool,
  ) -> [Int] {
    let letters = Array(word)

    return passages.map { passage in
      passage.weight * quality(
        ofWord: letters,
        in: passage.words,
        isExact: isExact,
      )
    }
  }

  private func quality(
    ofWord word: [Character],
    in words: [String],
    isExact: Bool,
  ) -> Int {
    var best = 0

    for candidate in words {
      let letters = Array(candidate)

      if letters == word {
        return TextMatch.exactQuality
      }

      guard !isExact else {
        continue
      }

      best = max(
        best,
        approximateQuality(
          ofWord: word,
          matching: letters,
        ),
      )
    }

    return best
  }

  /// A word start, or a typo: one wrong, missing, extra or swapped letter for a query word of 4
  /// letters or more, two for 8 or more.
  private func approximateQuality(
    ofWord word: [Character],
    matching candidate: [Character],
  ) -> Int {
    var best = 0

    if word.count >= Self.shortestWordStart, candidate.starts(with: word) {
      best = Self.wordStartQuality
    }

    guard let allowed = Self.typos(allowedIn: word.count) else {
      return best
    }

    switch distance.between(
      word,
      candidate,
      atMost: allowed,
    ) {
    case 1:
      best = max(best, Self.oneTypoQuality)
    case 2:
      best = max(best, Self.twoTyposQuality)
    default:
      break
    }

    return best
  }

  /// How many typos a query word of this length forgives; `nil` for none.
  private static func typos(allowedIn length: Int) -> Int? {
    switch length {
    case 8...:
      2
    case 4...:
      1
    default:
      nil
    }
  }

  /// Whether the words are in the passage's words next to each other, in order.
  private static func contains(
    _ phrase: [String],
    in words: [String],
  ) -> Bool {
    guard !phrase.isEmpty, phrase.count <= words.count else {
      return false
    }

    return (0 ... words.count - phrase.count).contains { start in
      Array(words[start ..< start + phrase.count]) == phrase
    }
  }

  /// The passages that matched, strongest first and in the order given among equals.
  private static func hits(of strengths: [Int]) -> [PassageHit] {
    var hits: [PassageHit] = []

    for (index, strength) in strengths.enumerated() where strength > 0 {
      hits.append(
        PassageHit(
          index: index,
          strength: strength,
        ),
      )
    }

    return hits.sorted { lhs, rhs in
      lhs.strength == rhs.strength ? lhs.index < rhs.index : lhs.strength > rhs.strength
    }
  }
}
