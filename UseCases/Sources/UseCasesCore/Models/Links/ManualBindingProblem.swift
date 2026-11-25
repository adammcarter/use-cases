/// Why a manual binding does not resolve, each one INVALID (chapter 09 §20.1).
enum ManualBindingProblem: Error, Equatable, Sendable {
  /// The file is not there as the binding spells it.
  case path(ExactPathError)

  /// The path names a folder, a pipe, a socket or a device, not a file.
  case notAFile(FileEntryKind)

  /// The file is there and cannot be read.
  case unreadable(FileSystemError)

  /// The range does not fit the file.
  case range(ManualRangeError)
}
