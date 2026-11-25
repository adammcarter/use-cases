/// What one fingerprinting call has read so far, so nothing is read twice (chapter 11 §73, §74).
struct FreshnessCaches: Sendable {
  /// The folders listed while resource paths were looked up.
  var listings = FolderListings()

  /// The bytes of every file read so far, links and resources alike: one read per path.
  var bytes: [WorkspacePath: [UInt8]] = [:]

  /// The SHA-256 of the exact bytes of each resource file that was read a chunk at a time and so
  /// is not in ``bytes``.
  var streamedDigests: [WorkspacePath: String] = [:]

  /// The whole-file reference of each resource file, under the run's policy.
  var references: [WorkspacePath: ContentReference] = [:]
}
