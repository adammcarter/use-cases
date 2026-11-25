/// The cards of a proposal, in the order new, extends, changes, replaces (chapter 21 §7).
public struct BriefLayout: Equatable, Sendable {
  public let cards: [BriefCard]

  /// A brief.
  public init(cards: [BriefCard]) {
    self.cards = cards
  }
}
