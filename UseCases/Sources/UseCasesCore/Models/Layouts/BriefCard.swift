/// The card of one use case a change adds, changes or removes (chapter 21 §7, step 4).
public struct BriefCard: Equatable, Sendable {
  /// The full id.
  public let useCase: String

  /// `new`, `extends`, `changes` or `replaces`: untouched use cases have no card.
  public let fit: ProposalFit

  public let title: String

  /// `critical`, `core` or `supporting`; `nil` when the use case has not chosen one.
  public let tier: String?

  /// What it promises from now on: its intent, or `Removed.` for a use case that goes.
  public let now: String

  /// What it promised before, when that changes.
  public let was: String?

  /// Its scenarios, golden path first as written; empty for a use case that goes.
  public let scenarios: [BriefScenario]

  /// What it does not include.
  public let notIncluded: [String]

  /// How it is proven, from its routes, in words a person reads.
  public let provenBy: [String]

  /// A card.
  public init(
    useCase: String,
    fit: ProposalFit,
    title: String,
    tier: String?,
    now: String,
    was: String?,
    scenarios: [BriefScenario],
    notIncluded: [String],
    provenBy: [String],
  ) {
    self.useCase = useCase
    self.fit = fit
    self.title = title
    self.tier = tier
    self.now = now
    self.was = was
    self.scenarios = scenarios
    self.notIncluded = notIncluded
    self.provenBy = provenBy
  }
}
