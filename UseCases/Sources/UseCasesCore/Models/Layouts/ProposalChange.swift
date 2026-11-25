/// One line of the proposal the person signs off (chapter 21 §7, step 5).
public struct ProposalChange: Equatable, Sendable {
  /// The full id.
  public let useCase: String

  public let fit: ProposalFit

  public let title: String

  /// `critical`, `core` or `supporting`; `nil` when the use case has not chosen one.
  public let tier: String?

  /// What the person will see, as the agent put it.
  public let youSee: String?

  /// A change.
  public init(
    useCase: String,
    fit: ProposalFit,
    title: String,
    tier: String?,
    youSee: String?,
  ) {
    self.useCase = useCase
    self.fit = fit
    self.title = title
    self.tier = tier
    self.youSee = youSee
  }
}
