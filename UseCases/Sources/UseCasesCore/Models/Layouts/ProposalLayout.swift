/// The whole change on one screen (chapter 21 §7, step 5).
public struct ProposalLayout: Equatable, Sendable {
  public let title: String

  /// One line for each use case the proposal names, in the order new, extends, changes,
  /// replaces, untouched.
  public let changes: [ProposalChange]

  public let decisions: [ProposalDecision]

  /// Who signs, by tier.
  public let signOff: SignOffCounts

  /// A proposal.
  public init(
    title: String,
    changes: [ProposalChange],
    decisions: [ProposalDecision],
    signOff: SignOffCounts,
  ) {
    self.title = title
    self.changes = changes
    self.decisions = decisions
    self.signOff = signOff
  }
}
