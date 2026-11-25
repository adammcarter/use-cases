extension RunCompletion {
  /// The marker as `completion.json` writes it (chapter 12 §20), or `nil` for a marker of a
  /// newer version, which has only its envelope and so cannot be written.
  var document: StoreJSONValue? {
    guard let details else {
      return nil
    }

    return .present([
      "completion_version": .integer(1),
      "run_id": .string(identifier.text),
      "finished_at": .string(details.finishedAt),
      "termination": .string(details.termination.rawValue),
      "result_count": .integer(resultCount),
      "manifest_sha256": .string(manifestDigest),
      "results_sha256": .string(resultsDigest),
      "outputs_sha256": Self.digestMap(details.outputDigests),
      "reports_sha256": Self.digestMap(details.reportDigests),
      "start_sha256": details.startDigest.map(StoreJSONValue.string),
    ])
  }

  private static func digestMap(_ digests: [FileDigest]) -> StoreJSONValue {
    .object(
      digests.map { digest in
        StoreJSONMember(
          key: digest.path,
          value: .string(digest.digest),
        )
      },
    )
  }
}
