/// What reading a file a chunk at a time found for the freshness of a route.
struct StreamedContent: Equatable, Sendable {
  /// The reference of the file's content after normalization.
  let reference: ContentReference

  /// The SHA-256 of the file's exact bytes, which `verify --start` keeps to name the files that
  /// moved during a run.
  let digest: String
}
