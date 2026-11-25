/// A descriptor of supplementary evidence kept with a result (chapter 12 §16). It resolves only
/// inside the run that holds it.
struct ResultAttachment: Equatable, Sendable {
  /// The text before the digest in a blob id.
  static let blobPrefix = "uc-blob-v1-sha256:"

  /// A non-empty display name, unique within the result; never a place on disk.
  let name: String

  /// The SHA-256 digest of the exact bytes: 64 lowercase hex digits.
  let digest: String

  /// The number of bytes.
  let sizeBytes: Int

  let mediaType: String?

  /// The blob id as the log writes it: `uc-blob-v1-sha256:<digest>`.
  var blob: String {
    Self.blobPrefix + digest
  }
}
