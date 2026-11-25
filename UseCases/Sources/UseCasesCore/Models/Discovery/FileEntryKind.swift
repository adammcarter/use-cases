/// What a folder entry is on disk, never looking through a symlink.
enum FileEntryKind: Sendable {
  case file
  case directory

  /// A symbolic link. Its target is never followed (chapter 04, "Symlinks").
  case symlink

  /// A socket, a pipe, a device. Never opened: reading a pipe can block forever.
  case other
}
