/// Opens the files of the store without ever following a symlink, and reads them as JSON.
protocol StoreFileAccessing: Sendable {
  /// What is at this place, without looking through a symlink; `nil` when nothing is.
  func kind(of file: StoreFile) throws(StoreProblem) -> FileEntryKind?

  /// The names in a folder.
  func entries(in folder: StoreFile) throws(StoreProblem) -> [FileEntry]

  /// The exact bytes of a file that has to be there. A sealed run missing it, or holding anything
  /// but a regular file in its place, is corrupt.
  func requiredBytes(of file: StoreFile) throws(StoreProblem) -> [UInt8]

  /// The bytes of a file below a folder, found by walking its path one name at a time so that no
  /// symlink on the way is followed. `nil` when a name on the way is not there.
  func bytes(
    below folder: StoreFile,
    path: String,
  ) throws(StoreProblem) -> [UInt8]?

  /// The SHA-256 and the length of a file found as ``bytes(below:path:)`` finds it, which is read a
  /// chunk at a time: a report or a blob is as big as the tests made it. `nil` when a name on the
  /// way is not there.
  func streamedFile(
    below folder: StoreFile,
    path: String,
    using hasher: any Hashing,
  ) throws(StoreProblem) -> StreamedFile?

  /// The path, relative to the folder, of everything below it that is not a folder, sorted. A
  /// symlink is listed and never followed. A folder that is not there has none.
  func files(below folder: StoreFile) throws(StoreProblem) -> [String]

  /// Reads bytes as one JSON document, refusing a byte order mark, text that is not UTF-8, and a
  /// duplicate key.
  func document(
    _ bytes: [UInt8],
    in file: StoreFile,
  ) throws(StoreProblem) -> AuthoredValue

  /// As ``document(_:in:)`` for one line of a log: errors name the line.
  func document(
    line bytes: [UInt8],
    number: Int,
    in file: StoreFile,
  ) throws(StoreProblem) -> AuthoredValue
}
