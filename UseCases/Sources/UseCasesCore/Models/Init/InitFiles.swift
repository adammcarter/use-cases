/// The files of `init` that are made and the ones that were already there.
struct InitFiles: Equatable {
  /// The writes that make the missing files, in the order of chapter 17 §8.
  let changes: [FileChange]

  /// The paths of those files.
  let created: [String]

  /// The paths of the wanted files that exist, which are left exactly as they are.
  let kept: [String]
}
