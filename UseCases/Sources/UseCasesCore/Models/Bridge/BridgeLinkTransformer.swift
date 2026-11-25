/// One entry of `links:` in the bridge settings: a transformer that adds links (chapter 10 §6).
struct BridgeLinkTransformer: Equatable, Sendable {
  let transformer: TransformerReference

  /// Passed to the transformer unchanged; `nil` when the entry has none.
  let settings: AuthoredValue?
}
