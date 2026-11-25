/// What is in the store for a run id a request names.
enum FoundRun: Equatable, Sendable {
  /// A verify run that is not sealed.
  case open(OpenVerifyRun)

  /// A record run that is not sealed: cut off mid-write, or being written. It has no start stamp,
  /// and `--abort` can close it (chapter 13 §15).
  case openRecord(RunIdentifier)

  /// A verify run that is not sealed and whose start stamp is missing or cannot be read.
  case damaged(DamagedRun)

  /// A run that is sealed.
  case sealed

  /// Nothing there.
  case missing
}
