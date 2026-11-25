/// What reading one validation's report came to (chapter 13 §7 step 3): the manifest entry for
/// the source and, when it could be read, the results the transformer gave.
struct SourceOutcome: Equatable, Sendable {
  /// The source as the manifest keeps it, with its `error` and its transformer's `diagnostics`.
  let source: RunSource

  /// One result for each validation link the transformer spoke for. Empty when the source has an
  /// error: no result of a source with a run error is used.
  let results: [TransformerLinkResult]

  /// The tests the transformer found inside no link. Empty when the source has an error.
  let unlinked: [UnlinkedTest]

  /// The report files as they were read, to be sealed in place of how they are at the seal
  /// (chapter 12 §15). Paths are relative to `reports/`.
  let readReports: [FileDigest]

  /// The request was cancelled while the report was read.
  let isCancelled: Bool

  /// The id of the validation.
  var identifier: IdentifierSegment {
    source.identifier
  }

  /// The manifest-level error: the validation's id, then what went wrong.
  var runError: String? {
    source.error.map { error in
      "\(source.identifier.text): \(error)"
    }
  }
}
