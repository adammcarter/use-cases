/// A results response once it is known to be shaped as chapter 10 §13 says.
struct TransformerResults: Equatable, Sendable {
  /// One result for each link the transformer spoke for, in the order it first spoke of them.
  /// Several results for one link are merged into one, the worst winning.
  let results: [TransformerLinkResult]

  /// The tests that fell inside no link.
  let unlinked: [UnlinkedTest]

  /// Words for people, which decide nothing.
  let diagnostics: [String]
}
