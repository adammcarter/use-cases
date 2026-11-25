/// One scenario of a card (chapter 21 §7).
public struct BriefScenario: Equatable, Sendable {
  /// Whether it is part of the golden path.
  public let isGolden: Bool

  /// The scenario in one line: `given G: W → T`, with no `given` when there is none.
  public let text: String

  /// A scenario of a card.
  public init(
    isGolden: Bool,
    text: String,
  ) {
    self.isGolden = isGolden
    self.text = text
  }
}
