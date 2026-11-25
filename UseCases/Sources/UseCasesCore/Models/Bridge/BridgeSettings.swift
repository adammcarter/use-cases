/// The root `use-cases-bridge.yml` once it passed its schema and the checks on the file
/// (chapter 10, chapter 09 §21). Nothing in it is run, and nothing in it changes a route
/// fingerprint (chapter 10 §4).
struct BridgeSettings: Equatable, Sendable {
  /// The link transformers, in the order written.
  let links: [BridgeLinkTransformer]

  /// The validations, in the order written, which is the order `--run` runs them.
  let validations: [BridgeValidation]
}
