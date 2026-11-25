/// One route's verdict in one run (chapter 12 §12). A run holds at most one per use case + route.
///
/// The first four members are the envelope every record version keeps (chapter 12 §25). A record
/// of a version this core does not know has no `detail`: it counts for status, and nothing else of
/// it is read.
struct StoredResult: Equatable, Sendable {
  let useCase: UseCaseIdentifier
  let route: RouteIdentifier

  /// The route fingerprint at the start point of the run.
  let fingerprint: RouteFingerprint

  let verdict: Verdict

  /// `nil` for a record of a newer version.
  let detail: StoredResultDetail?
}
