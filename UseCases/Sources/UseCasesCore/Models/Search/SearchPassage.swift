/// One piece of text a search looks in, with how much a match in it counts. A use case's title is
/// one; a guide's heading is another.
struct SearchPassage: Equatable, Sendable {
  /// How much a match here counts, 1 to ``TextMatch/bestWeight``.
  let weight: Int

  /// The text as written.
  let text: String

  /// The words of the text, lower case, in order.
  let words: [String]

  init(
    weight: Int,
    text: String,
  ) {
    self.weight = weight
    self.text = text
    words = text.searchWords
  }
}
