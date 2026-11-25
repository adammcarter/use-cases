/// What reading a file through to its end found: the SHA-256 of its exact bytes, and how many
/// there were.
struct StreamedFile: Equatable, Sendable {
  /// 64 lowercase hexadecimal characters.
  let digest: String

  /// The bytes that were read, which is not always what the file's size said when it was opened.
  let length: Int
}
