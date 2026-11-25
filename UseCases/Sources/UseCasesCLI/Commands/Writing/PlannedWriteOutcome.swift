/// What became of a plan the shared writer was given.
enum PlannedWriteOutcome: Equatable {
  /// `--dry-run`: the plan was checked and nothing was written.
  case previewed

  /// The plan was written.
  case written

  /// The request was cancelled after the write had begun, so the write was finished.
  case writtenAfterCancellation

  /// The request was cancelled before the write began, so nothing was written.
  case cancelled
}
