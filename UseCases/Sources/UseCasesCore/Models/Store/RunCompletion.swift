/// The commit point of a run (`completion.json`, chapter 12 §20).
///
/// The envelope is what every version keeps (chapter 12 §25). `details` is present for a marker of
/// a version this core reads.
struct RunCompletion: Equatable, Sendable {
  let version: Int
  let identifier: RunIdentifier
  let resultCount: Int

  /// The SHA-256 of the exact bytes of `run.json`.
  let manifestDigest: String

  /// The SHA-256 of the exact bytes of `results.jsonl`.
  let resultsDigest: String

  let details: Details?

  /// What a marker of a supported version holds beyond the envelope.
  struct Details: Equatable, Sendable {
    let finishedAt: String
    let termination: RunTermination

    /// The SHA-256 of every file under `outputs/`, by path relative to it, in the order written.
    let outputDigests: [FileDigest]

    /// The SHA-256 of every file under `reports/`, by path relative to it, as it was read.
    let reportDigests: [FileDigest]

    /// The SHA-256 of `start.json`, present exactly when the run has one.
    let startDigest: String?
  }
}
