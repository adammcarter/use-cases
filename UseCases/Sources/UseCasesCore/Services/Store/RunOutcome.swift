/// What reading one run folder found.
enum RunOutcome: Equatable, Sendable {
  /// A sealed run whose every check passed.
  case sealed(StoredRun)

  /// A folder with no completion marker.
  case unfinished(UnfinishedRun)

  /// A sealed run that cannot be used, with everything wrong with it.
  case damaged([StoreProblem])
}
