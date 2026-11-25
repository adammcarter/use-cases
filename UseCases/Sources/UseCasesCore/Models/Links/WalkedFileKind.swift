/// What a file the code walk found is, which decides how the scan reads it.
enum WalkedFileKind: Equatable, Sendable {
  /// A regular file: read as stored.
  case file

  /// A symlink: never followed, and read as the text it points with.
  case symlink
}
