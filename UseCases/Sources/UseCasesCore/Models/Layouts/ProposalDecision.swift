/// A choice the person makes, which the agent never makes for them (chapter 21 §5).
public struct ProposalDecision: Equatable, Sendable {
  public let question: String

  /// At least two.
  public let options: [String]

  /// A decision.
  public init(
    question: String,
    options: [String],
  ) {
    self.question = question
    self.options = options
  }
}
