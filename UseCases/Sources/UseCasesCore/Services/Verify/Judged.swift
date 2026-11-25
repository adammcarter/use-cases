/// What judging the READY routes of a run came to: the verdicts to store and the reasons the
/// other routes have none.
struct Judged: Equatable, Sendable {
  let results: [StoredResult]

  /// Link warnings first, then one for each route that got no verdict, in the order of the
  /// workspace.
  let diagnostics: [RunDiagnostic]
}
