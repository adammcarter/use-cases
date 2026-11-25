/// A sealed run that passed every check a reader makes (chapter 12 §22): its verdicts count.
struct StoredRun: Equatable, Sendable {
  let identifier: RunIdentifier
  let completion: RunCompletion

  /// `nil` when the manifest is of a version this core does not read; only the envelope was.
  let manifest: RunManifest?

  /// At most one per use case + route, in the order the log gives them (which carries no meaning).
  let results: [StoredResult]

  /// Damage to reports and attachments, beside the verdicts.
  let findings: [RunIntegrityFinding]

  /// How the run ended; `nil` when the marker is of a version this core does not read.
  var termination: RunTermination? {
    completion.details?.termination
  }
}
