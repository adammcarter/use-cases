/// What a search looks for, once the words typed are read (chapter 16 §15). Every word is lower
/// case and has no punctuation.
struct SearchQuery: Equatable, Sendable {
  /// A use case needs at least one of these, when there are any.
  let words: [String]

  /// Each must appear, its words next to each other and in this order.
  let phrases: [[String]]

  /// A use case with any of these, a word or a phrase, is left out.
  let exclusions: [[String]]

  /// Whether a word matches only whole words as typed, with no word start and no typo.
  let isExact: Bool

  /// Every word and phrase that counts towards the ranking.
  var termCount: Int {
    words.count + phrases.count
  }

  /// A query with nothing to look for: a search with it is refused.
  var isEmpty: Bool {
    words.isEmpty && phrases.isEmpty
  }
}
