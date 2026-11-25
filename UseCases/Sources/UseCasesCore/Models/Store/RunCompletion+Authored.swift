extension RunCompletion {
  /// Reads a marker of version 1, after it passed the completion schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let startDigest = try object.optionalString("start_sha256")

    try self.init(
      envelopeOf: object,
      details: Details(
        finishedAt: object.requiredString("finished_at"),
        termination: object.requiredChoice(
          "termination",
          as: RunTermination.self,
        ),
        outputDigests: object.textMembers("outputs_sha256"),
        reportDigests: object.textMembers("reports_sha256"),
        startDigest: startDigest,
      ),
    )
  }

  /// Reads the envelope every marker version keeps: run id, result count and the two digests.
  init(envelopeOf object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      envelopeOf: object,
      details: nil,
    )
  }

  private init(
    envelopeOf object: AuthoredObject,
    details: Details?,
  ) throws(AuthoredShapeError) {
    try self.init(
      version: object.requiredInteger("completion_version"),
      identifier: object.requiredRunIdentifier("run_id"),
      resultCount: object.requiredCount("result_count"),
      manifestDigest: object.requiredString("manifest_sha256"),
      resultsDigest: object.requiredString("results_sha256"),
      details: details,
    )
  }
}
