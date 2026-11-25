import Foundation

/// Reads the folders and files discovery looks at, and never follows a symlink to do it.
protocol FileSystemReading: Sendable {
  /// The absolute location with every symlink resolved and `.` and `..` removed.
  func canonicalLocation(of url: URL) -> URL

  /// What is at this location, without following a symlink there; `nil` when nothing is.
  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind?

  /// Every name in a folder, with what it is. The order is whatever the system gives: callers
  /// never depend on it.
  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry]

  /// The text of a regular file. Callers use it only on what `kindOfItem` called a file.
  func readText(at file: URL) throws(FileSystemError) -> String

  /// The bytes of a regular file, exactly as stored. Callers use it only on what `kindOfItem`
  /// called a file: it would follow a symlink.
  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8]

  /// A regular file to be read a chunk at a time, exactly as stored, for what is too big to hold:
  /// hashing it, or copying it. The same file as ``readBytes(at:)`` reads, and the same errors.
  func chunks(of file: URL) throws(FileSystemError) -> any FileChunkReading

  /// The text a symlink holds: where it points, as written, never what is there. Callers use it
  /// only on what `kindOfItem` called a symlink.
  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String

  /// Whether a file or symlink with exactly this name is in the folder `folder` of `parent`, or in
  /// a folder below it. The folder is found by its name's bytes, so a name that is not valid
  /// UTF-8 can be searched. A symlink is never followed, and a folder that cannot be read has
  /// nothing found in it.
  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool
}

extension FileSystemReading {
  /// A file system that cannot stream gives its file whole, and it is handed out in chunks.
  func chunks(of file: URL) throws(FileSystemError) -> any FileChunkReading {
    try BufferedChunkReader(bytes: readBytes(at: file))
  }
}
