/// One section of a guide that matched a search of the guides.
public struct GuideMatch: Equatable, Sendable {
  /// The name of the guide.
  public let guide: String

  /// The section's heading.
  public let section: String

  /// The section's text on one line, cut to ``SearchReason/longestText`` characters.
  public let text: String

  /// From 0.0001 to 1, in ten-thousandths. It orders the results of one search and means nothing
  /// beside another search's.
  public let score: Double

  /// A match.
  public init(
    guide: String,
    section: String,
    text: String,
    score: Double,
  ) {
    self.guide = guide
    self.section = section
    self.text = text
    self.score = score
  }
}
