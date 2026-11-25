/// The keys of a proposal file beside the batch, read and held to their shapes (chapter 21 §7).
struct ProposalPresentation: Equatable, Sendable {
  let title: String
  let untouched: [String]
  let fits: [String: ProposalFit]
  let youSee: [String: String]
  let decisions: [ProposalDecision]
  let golden: [String: [String]]

  /// Reads the presentation keys of the mapping, which holds no key a proposal does not.
  init(
    reading object: AuthoredObject,
    named name: String,
  ) throws(LayoutRenderingError) {
    let reading = ProposalKeys(
      object: object,
      name: name,
    )

    title = try reading.title()
    untouched = try reading.untouchedOnce()
    fits = try reading.fits()
    youSee = try reading.youSee()
    decisions = try reading.decisions()
    golden = try reading.golden()
  }
}
