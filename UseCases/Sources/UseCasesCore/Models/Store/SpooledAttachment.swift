import Foundation

/// A file given as evidence, as it was when the request was checked: kept in a file of its own
/// until the verdict is committed, with the digest and the number of bytes that were kept
/// (chapter 12 §17). What the person's file becomes afterwards changes nothing.
struct SpooledAttachment: Equatable, Sendable {
  /// The last name of the path it came from. Never a place on disk (chapter 12 §16).
  let name: String

  /// The kept copy.
  let file: URL

  /// The SHA-256 of the exact bytes that were kept.
  let digest: String

  /// How many bytes were kept.
  let length: Int
}
