/// What a run is made of when it is published (chapter 12 §11): its files, and whether the one
/// who publishes it holds it from the first moment.
struct RunPublication {
  let identifier: RunIdentifier
  let manifestBytes: [UInt8]

  /// `start.json`; `nil` for a record run.
  let stamp: [UInt8]?

  /// The validations that get an empty reports folder.
  let reportFolders: [IdentifierSegment]

  /// Whether the run's lock is taken before the run is published.
  let holdsLock: Bool
}
