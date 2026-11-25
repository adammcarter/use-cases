/// Why a path a workspace names is not a file there as it is spelled (chapter 04 "Path spelling").
enum ExactPathError: Error, Equatable, Sendable {
  /// Nothing is there. A file where a folder should be counts too.
  case missing

  /// A name on the way, or the last one, is there only under another spelling: another case or
  /// another Unicode form.
  case spelledDifferently(
    written: String,
    onDisk: String,
  )

  /// A symlink stands on the way, and a symlink is never followed.
  case behindSymlink(WorkspacePath)

  /// A folder on the way cannot be listed.
  case unreadableFolder(
    WorkspacePath,
    FileSystemError,
  )
}
