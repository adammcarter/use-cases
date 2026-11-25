import Foundation

/// Writes the files of the store in the ways chapter 12 asks for: new files that never replace
/// one, files replaced whole by a rename, folders published whole by a rename, and everything
/// flushed to disk before it is relied on.
protocol StoreFileWriting: Sendable {
  /// Makes a folder if it is not there. A folder that is there is fine; anything else in its
  /// place is an error. The parent has to exist.
  func ensureFolder(at folder: URL) throws(StoreWritingError)

  /// Writes a file that is not there yet and flushes it. A file that is there is an error.
  func createFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError)

  /// Replaces a file, or makes it, by writing a temporary file beside it and renaming that over
  /// it. A reader sees the old bytes or the new ones, never a mix.
  func replaceFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError)

  /// Adds bytes to the end of a file that is there, and flushes it.
  func append(
    _ bytes: [UInt8],
    to file: URL,
  ) throws(StoreWritingError)

  /// Makes a file appear whole and never over another: the bytes are written beside it, then
  /// linked into place, which fails when something is already there.
  func publishFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError)

  /// Makes a file appear whole, never over another, and runnable by its owner and everyone who
  /// can read it: it is runnable from the moment it has a name.
  func publishExecutableFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError)

  /// Renames a folder to its final name. Something already at that name is an error. The parent
  /// is flushed so the rename survives a crash.
  func publishFolder(
    _ folder: URL,
    as published: URL,
  ) throws(StoreWritingError)

  /// Flushes the names in a folder, so that a file or folder made in it survives a crash.
  func flushFolder(at folder: URL) throws(StoreWritingError)

  /// Removes what a failed write left behind. It never fails: there is nothing more to do.
  func discard(_ item: URL)
}

extension StoreFileWriting {
  /// A writer that does not stage files itself stages them as the machine's file system does.
  func stageFile(
    copying source: any FileChunkReading,
    in folder: URL,
  ) throws(StoreWritingError) -> URL {
    try LocalStoreFileWriter().stageFile(
      copying: source,
      in: folder,
    )
  }

  func publishStagedFile(
    _ staged: URL,
    at file: URL,
  ) throws(StoreWritingError) {
    try LocalStoreFileWriter().publishStagedFile(
      staged,
      at: file,
    )
  }
}
